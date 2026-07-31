package baseline

import (
	"bytes"
	"encoding/json"
	"os"
	"os/exec"
	"sync"
	"time"

	"simulator/internal/constants"
)

// unschedulableSample mirrors the schema analyzer/data_loader.py::load_unschedulable_data
// expects, one JSON object per line:
//
//	{"timestamp": "2026-07-20 21:34:59", "unschedulable_count": 2,
//	 "unschedulable_workloads": ["default/12-345-deployment", ...]}
type unschedulableSample struct {
	Timestamp              string   `json:"timestamp"`
	UnschedulableCount     int      `json:"unschedulable_count"`
	UnschedulableWorkloads []string `json:"unschedulable_workloads"`
}

// UnschedulablePoller periodically queries the karmada-apiserver for
// ResourceBindings with condition Scheduled=False — workloads karmada-scheduler
// couldn't assign to any cluster at all, which never show up as Pending pods
// in metrics.json (they never get propagated). It is the safety net that
// makes a silent total-scheduling failure visible to the analyzer.
//
// Only meaningful for baseline runs (see config.IsAIDisabledByEnv); the
// AI-driven flow never starts one, and the analyzer treats a missing
// unschedulable_bindings.jsonl as "not applicable", not an error.
type UnschedulablePoller struct {
	interval time.Duration
	stopCh   chan struct{}
	doneCh   chan struct{}

	mu      sync.Mutex
	samples []unschedulableSample
}

// NewUnschedulablePoller creates a poller that samples every interval.
func NewUnschedulablePoller(interval time.Duration) *UnschedulablePoller {
	return &UnschedulablePoller{
		interval: interval,
		stopCh:   make(chan struct{}),
		doneCh:   make(chan struct{}),
	}
}

// Start begins polling in the background. Call Stop to end it.
func (p *UnschedulablePoller) Start() {
	go func() {
		defer close(p.doneCh)
		p.sample()

		ticker := time.NewTicker(p.interval)
		defer ticker.Stop()
		for {
			select {
			case <-p.stopCh:
				return
			case <-ticker.C:
				p.sample()
			}
		}
	}()
}

// Stop ends the polling loop and waits for the in-flight sample to finish.
func (p *UnschedulablePoller) Stop() {
	close(p.stopCh)
	<-p.doneCh
}

// resourceBindingList is the subset of `kubectl get resourcebinding -A -o json`
// this poller needs.
type resourceBindingList struct {
	Items []struct {
		Metadata struct {
			Namespace string `json:"namespace"`
			Name      string `json:"name"`
		} `json:"metadata"`
		Status struct {
			Conditions []struct {
				Type   string `json:"type"`
				Status string `json:"status"`
			} `json:"conditions"`
		} `json:"status"`
	} `json:"items"`
}

func (p *UnschedulablePoller) sample() {
	ts := time.Now().Format("2006-01-02 15:04:05")

	cmd := exec.Command(
		"docker", "exec", constants.ContainerInfraEnvironment,
		"kubectl",
		"--kubeconfig", constants.KarmadaKubeconfigPath,
		"--context", constants.KarmadaAPIServerContext,
		"get", "resourcebinding", "-A", "-o", "json",
	)
	out, err := cmd.Output()
	if err != nil {
		// Matches the previous bash poller: a failed sample (e.g. API server
		// briefly unreachable) is skipped rather than treated as fatal.
		return
	}

	var list resourceBindingList
	if err := json.Unmarshal(out, &list); err != nil {
		return
	}

	unschedulable := make([]string, 0)
	for _, item := range list.Items {
		for _, cond := range item.Status.Conditions {
			if cond.Type != "Scheduled" {
				continue
			}
			if cond.Status == "False" {
				unschedulable = append(unschedulable, item.Metadata.Namespace+"/"+item.Metadata.Name)
			}
			break // only the first "Scheduled" condition counts
		}
	}

	sample := unschedulableSample{
		Timestamp:              ts,
		UnschedulableCount:     len(unschedulable),
		UnschedulableWorkloads: unschedulable,
	}

	p.mu.Lock()
	p.samples = append(p.samples, sample)
	p.mu.Unlock()
}

// WriteJSONL writes every collected sample, one JSON object per line, to path.
func (p *UnschedulablePoller) WriteJSONL(path string) error {
	p.mu.Lock()
	defer p.mu.Unlock()

	var buf bytes.Buffer
	enc := json.NewEncoder(&buf)
	for _, s := range p.samples {
		if err := enc.Encode(s); err != nil {
			return err
		}
	}
	return os.WriteFile(path, buf.Bytes(), 0644)
}
