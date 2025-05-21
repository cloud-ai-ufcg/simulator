package collector

import (
	"context"
	"fmt"
	"time"

	"monitor/internal/config"
	"monitor/internal/model"
	"github.com/prometheus/client_golang/api"
	v1 "github.com/prometheus/client_golang/api/prometheus/v1"
	prommodel "github.com/prometheus/common/model"
)

// Prometheus query constants
const (
	queryCPUCapacity      = `sum(kube_node_status_capacity{resource="cpu"})`
	queryMemoryCapacity   = `sum(kube_node_status_capacity{resource="memory"})`
	queryTotalCPUUsage    = `sum(kube_pod_container_resource_requests{resource="cpu"})`
	queryTotalMemoryUsage = `sum(kube_pod_container_resource_requests{resource="memory"})`
)

// QueryBuilder helps construct Prometheus queries
type QueryBuilder struct {
	kind      string
	namespace string
	name      string
}

func NewQueryBuilder(kind, namespace, name string) *QueryBuilder {
	return &QueryBuilder{
		kind:      kind,
		namespace: namespace,
		name:      name,
	}
}

func (qb *QueryBuilder) WorkloadCreated() string {
	return fmt.Sprintf(`kube_%s_created{namespace="%s"}`, qb.kind, qb.namespace)
}

func (qb *QueryBuilder) TotalPods() string {
	if qb.kind == "job" {
		// For jobs, we need to sum active and failed pods
		return fmt.Sprintf(`sum(kube_job_status_active{namespace="%s",job_name="%s"} + kube_job_status_failed{namespace="%s",job_name="%s"})`,
			qb.namespace, qb.name, qb.namespace, qb.name)
	}
	// For deployments, use the original query
	return fmt.Sprintf(`kube_%s_status_replicas{namespace="%s",%s="%s"}`, qb.kind, qb.namespace, qb.kind, qb.name)
}

func (qb *QueryBuilder) AvailablePods() string {
	if qb.kind == "job" {
		// For jobs, we consider active pods as available
		return fmt.Sprintf(`kube_job_status_active{namespace="%s",job_name="%s"}`, qb.namespace, qb.name)
	}
	// For deployments, use the original query
	return fmt.Sprintf(`kube_%s_status_replicas_available{namespace="%s",%s="%s"}`, qb.kind, qb.namespace, qb.kind, qb.name)
}

func (qb *QueryBuilder) ResourceRequests(resource string) string {
	return fmt.Sprintf(`sum(kube_pod_container_resource_requests{namespace="%s",pod=~"%s-.*",resource="%s"})`, qb.namespace, qb.name, resource)
}

// WorkloadMetrics represents the metrics for a single workload
type WorkloadMetrics struct {
	TotalPods     int
	AvailablePods int
	CPURequest    float64
	MemoryRequest float64
}

type Collector struct {
	cfg     *config.Config
	clients map[string]v1.API
}

func NewCollector(cfg *config.Config) *Collector {
	clients := make(map[string]v1.API)
	for _, cluster := range cfg.Clusters {
		client, err := api.NewClient(api.Config{
			Address: cluster.PrometheusURL,
		})
		if err != nil {
			panic(fmt.Sprintf("Error creating Prometheus client for cluster %s: %v", cluster.Label, err))
		}
		v1Client := v1.NewAPI(client)
		clients[cluster.Label] = v1Client
	}

	return &Collector{
		cfg:     cfg,
		clients: clients,
	}
}

func (c *Collector) CollectMetrics() (map[int64]model.MetricsOutput, error) {
	metricsByTimestamp := make(map[int64]model.MetricsOutput)
	ctx := context.Background()
	timestamp := time.Now().Unix()

	// Initialize the metrics output for this timestamp
	metricsByTimestamp[timestamp] = model.MetricsOutput{
		Workloads:   make([]model.Workload, 0),
		ClusterInfo: make([]model.ClusterInfo, 0),
	}

	for _, cluster := range c.cfg.Clusters {
		client := c.clients[cluster.Label]

		// Query cluster capacity and usage for cluster info
		clusterInfo, err := c.queryClusterInfo(ctx, client, cluster.Label)
		if err != nil {
			return nil, fmt.Errorf("error querying cluster info: %v", err)
		}
		metrics := metricsByTimestamp[timestamp]
		metrics.ClusterInfo = append(metrics.ClusterInfo, clusterInfo)
		metricsByTimestamp[timestamp] = metrics

		// Query for deployments
		deploymentMetrics, err := c.queryWorkloadMetrics(ctx, client, "deployment", cluster.Label)
		if err != nil {
			return nil, fmt.Errorf("error querying deployment metrics: %v", err)
		}
		metrics = metricsByTimestamp[timestamp]
		metrics.Workloads = append(metrics.Workloads, deploymentMetrics...)
		metricsByTimestamp[timestamp] = metrics

		// Query for jobs
		jobMetrics, err := c.queryWorkloadMetrics(ctx, client, "job", cluster.Label)
		if err != nil {
			return nil, fmt.Errorf("error querying job metrics: %v", err)
		}
		metrics = metricsByTimestamp[timestamp]
		metrics.Workloads = append(metrics.Workloads, jobMetrics...)
		metricsByTimestamp[timestamp] = metrics
	}

	return metricsByTimestamp, nil
}

func (c *Collector) queryClusterInfo(ctx context.Context, client v1.API, clusterLabel string) (model.ClusterInfo, error) {
	// Query cluster capacity
	cpuCapacityResult, _, err := client.Query(ctx, queryCPUCapacity, time.Now())
	if err != nil {
		return model.ClusterInfo{}, fmt.Errorf("error querying CPU capacity: %v", err)
	}

	memoryCapacityResult, _, err := client.Query(ctx, queryMemoryCapacity, time.Now())
	if err != nil {
		return model.ClusterInfo{}, fmt.Errorf("error querying memory capacity: %v", err)
	}

	// Query total resource usage across all namespaces
	totalCPUUsageResult, _, err := client.Query(ctx, queryTotalCPUUsage, time.Now())
	if err != nil {
		return model.ClusterInfo{}, fmt.Errorf("error querying total CPU usage: %v", err)
	}

	totalMemoryUsageResult, _, err := client.Query(ctx, queryTotalMemoryUsage, time.Now())
	if err != nil {
		return model.ClusterInfo{}, fmt.Errorf("error querying total memory usage: %v", err)
	}

	// Process cluster capacity and usage results
	var clusterCPUCapacity, clusterMemoryCapacity string
	var clusterLoadCPU, clusterLoadMemory float64

	if cpuVector, ok := cpuCapacityResult.(prommodel.Vector); ok && len(cpuVector) > 0 {
		cpuCores := float64(cpuVector[0].Value)
		clusterCPUCapacity = fmt.Sprintf("%dm", int(cpuCores*1000)) // Convert cores to millicores

		// Calculate CPU load percentage
		if cpuUsageVector, ok := totalCPUUsageResult.(prommodel.Vector); ok && len(cpuUsageVector) > 0 {
			cpuUsage := float64(cpuUsageVector[0].Value)
			clusterLoadCPU = cpuUsage / cpuCores // Now returns value between 0 and 1
		}
	}

	if memoryVector, ok := memoryCapacityResult.(prommodel.Vector); ok && len(memoryVector) > 0 {
		memoryBytes := float64(memoryVector[0].Value)
		memoryMiB := memoryBytes / (1024 * 1024) // Convert bytes to MiB
		clusterMemoryCapacity = fmt.Sprintf("%dMi", int(memoryMiB))

		// Calculate memory load percentage
		if memoryUsageVector, ok := totalMemoryUsageResult.(prommodel.Vector); ok && len(memoryUsageVector) > 0 {
			memoryUsage := float64(memoryUsageVector[0].Value)
			clusterLoadMemory = memoryUsage / memoryBytes // Now returns value between 0 and 1
		}
	}

	return model.ClusterInfo{
		ClusterLabel: clusterLabel,
		ClusterLoad: model.ClusterLoad{
			CPU:    float64(int(clusterLoadCPU*1000)) / 1000,    // Truncate to 3 decimal places
			Memory: float64(int(clusterLoadMemory*1000)) / 1000, // Truncate to 3 decimal places
		},
		ClusterCPUCapacity:    clusterCPUCapacity,
		ClusterMemoryCapacity: clusterMemoryCapacity,
	}, nil
}

func (c *Collector) queryWorkloadMetrics(ctx context.Context, client v1.API, kind string, clusterLabel string) ([]model.Workload, error) {
	var workloads []model.Workload

	// Query to get all workload names
	workloadsQuery := fmt.Sprintf(`kube_%s_created{namespace="default"}`, kind)
	workloadsResult, warnings, err := client.Query(ctx, workloadsQuery, time.Now())
	if err != nil {
		return nil, err
	}
	if len(warnings) > 0 {
		fmt.Printf("Warnings for workloads query: %v\n", warnings)
	}

	// Process each workload
	if workloadsVector, ok := workloadsResult.(prommodel.Vector); ok {
		for _, workload := range workloadsVector {
			// Extract name and namespace from the metric labels
			var name string
			if kind == "deployment" {
				name = string(workload.Metric["deployment"])
			} else if kind == "job" {
				name = string(workload.Metric["job_name"])
			}
			namespace := string(workload.Metric["namespace"])

			// Get metrics for this workload
			metrics, err := c.getWorkloadMetrics(ctx, client, kind, namespace, name)
			if err != nil {
				fmt.Printf("Error getting metrics for %s/%s: %v\n", namespace, name, err)
				continue
			}

			// Calculate pending pods and percentage
			pendingPods := metrics.TotalPods - metrics.AvailablePods
			percentPending := 0.0
			if metrics.TotalPods > 0 {
				percentPending = float64(pendingPods) / float64(metrics.TotalPods) * 100
			}

			// Create workload entry
			workload := model.Workload{
				WorkloadID: fmt.Sprintf("%s/%s", namespace, name),
				Kind:       kind,
				Resources: model.Resources{
					CPU:    fmt.Sprintf("%dm", int(metrics.CPURequest*1000)),
					Memory: fmt.Sprintf("%dMi", int(metrics.MemoryRequest/(1024*1024))),
				},
				PodsTotal:      metrics.TotalPods,
				PodsPending:    pendingPods,
				PercentPending: percentPending,
				ClusterLabel:   clusterLabel,
			}
			workloads = append(workloads, workload)
		}
	}

	return workloads, nil
}

func (c *Collector) getWorkloadMetrics(ctx context.Context, client v1.API, kind, namespace, name string) (WorkloadMetrics, error) {
	qb := NewQueryBuilder(kind, namespace, name)
	var metrics WorkloadMetrics

	// Query for total pods
	totalPodsResult, _, err := client.Query(ctx, qb.TotalPods(), time.Now())
	if err != nil {
		return metrics, fmt.Errorf("error querying total pods: %v", err)
	}

	// Query for available pods
	availablePodsResult, _, err := client.Query(ctx, qb.AvailablePods(), time.Now())
	if err != nil {
		return metrics, fmt.Errorf("error querying available pods: %v", err)
	}

	// Query for resource requests
	cpuResult, _, err := client.Query(ctx, qb.ResourceRequests("cpu"), time.Now())
	if err != nil {
		return metrics, fmt.Errorf("error querying CPU: %v", err)
	}

	memoryResult, _, err := client.Query(ctx, qb.ResourceRequests("memory"), time.Now())
	if err != nil {
		return metrics, fmt.Errorf("error querying memory: %v", err)
	}

	// Process results
	if totalVector, ok := totalPodsResult.(prommodel.Vector); ok && len(totalVector) > 0 {
		metrics.TotalPods = int(totalVector[0].Value)
	}

	if availableVector, ok := availablePodsResult.(prommodel.Vector); ok && len(availableVector) > 0 {
		metrics.AvailablePods = int(availableVector[0].Value)
	}

	if cpuVector, ok := cpuResult.(prommodel.Vector); ok && len(cpuVector) > 0 {
		metrics.CPURequest = float64(cpuVector[0].Value)
	}

	if memoryVector, ok := memoryResult.(prommodel.Vector); ok && len(memoryVector) > 0 {
		metrics.MemoryRequest = float64(memoryVector[0].Value)
	}

	return metrics, nil
}
