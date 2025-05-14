package monitor

import (
	"context"
	"fmt"
	"path/filepath"
	"strconv"
	"time"

	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/client-go/kubernetes"
	"k8s.io/client-go/rest"
	"k8s.io/client-go/tools/clientcmd"
	"k8s.io/client-go/util/homedir"

	"monitor/pkg/writer"
)

// KubernetesMonitor handles the monitoring of Kubernetes resources
type KubernetesMonitor struct {
	clientset     *kubernetes.Clientset
	podWriter     *writer.CSVWriter
	nodeWriter    *writer.CSVWriter
	clusterWriter *writer.CSVWriter
}

// NewKubernetesMonitor creates a new instance of KubernetesMonitor
func NewKubernetesMonitor() (*KubernetesMonitor, error) {
	config, err := getKubernetesConfig()
	if err != nil {
		return nil, fmt.Errorf("error creating kubernetes config: %v", err)
	}

	clientset, err := kubernetes.NewForConfig(config)
	if err != nil {
		return nil, fmt.Errorf("error creating kubernetes client: %v", err)
	}

	podWriter, err := writer.NewCSVWriter("pod_metrics.csv", []string{
		"Timestamp", "ID", "Status", "Node", "Cluster", "RequestedCPU", "RequestedMem",
	})
	if err != nil {
		return nil, fmt.Errorf("error creating pod writer: %v", err)
	}

	nodeWriter, err := writer.NewCSVWriter("node_metrics.csv", []string{
		"Timestamp", "ID", "TotalCPU", "TotalMemory", "Cluster",
	})
	if err != nil {
		podWriter.Close()
		return nil, fmt.Errorf("error creating node writer: %v", err)
	}

	clusterWriter, err := writer.NewCSVWriter("cluster_metrics.csv", []string{
		"Timestamp", "ID", "TotalCPU", "TotalMemory", "AllocatedCPU", "AllocatedMemory", "CPUUtilization", "MemoryUtilization",
	})
	if err != nil {
		podWriter.Close()
		nodeWriter.Close()
		return nil, fmt.Errorf("error creating cluster writer: %v", err)
	}

	return &KubernetesMonitor{
		clientset:     clientset,
		podWriter:     podWriter,
		nodeWriter:    nodeWriter,
		clusterWriter: clusterWriter,
	}, nil
}

// getKubernetesConfig returns the Kubernetes configuration
func getKubernetesConfig() (*rest.Config, error) {
	if home := homedir.HomeDir(); home != "" {
		kubeconfig := filepath.Join(home, ".kube", "config")
		config, err := clientcmd.BuildConfigFromFlags("", kubeconfig)
		if err == nil {
			return config, nil
		}
	}
	return rest.InClusterConfig()
}

// Close closes all writers
func (m *KubernetesMonitor) Close() {
	m.podWriter.Close()
	m.nodeWriter.Close()
	m.clusterWriter.Close()
}

// CollectMetrics starts collecting metrics from the Kubernetes cluster
func (m *KubernetesMonitor) CollectMetrics(ctx context.Context) {
	ticker := time.NewTicker(3 * time.Second)
	defer ticker.Stop()

	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			m.collectAndWriteMetrics(ctx)
		}
	}
}

// collectAndWriteMetrics collects and writes metrics to CSV files
func (m *KubernetesMonitor) collectAndWriteMetrics(ctx context.Context) {
	timestamp := time.Now().Format(time.RFC3339)

	pods, err := m.clientset.CoreV1().Pods("").List(ctx, metav1.ListOptions{})
	if err == nil {
		m.writePodMetrics(pods.Items, timestamp)
	}

	nodes, err := m.clientset.CoreV1().Nodes().List(ctx, metav1.ListOptions{})
	if err == nil {
		totalCPU, totalMem := m.writeNodeMetrics(nodes.Items, timestamp)
		if pods != nil {
			m.writeClusterMetrics(pods.Items, totalCPU, totalMem, timestamp)
		}
	}
}

func (m *KubernetesMonitor) writePodMetrics(pods []corev1.Pod, timestamp string) {
	for _, pod := range pods {
		for _, container := range pod.Spec.Containers {
			m.podWriter.Write([]string{
				timestamp,
				string(pod.UID),
				string(pod.Status.Phase),
				pod.Spec.NodeName,
				pod.Labels["cluster"],
				container.Resources.Requests.Cpu().String(),
				container.Resources.Requests.Memory().String(),
			})
		}
	}
	m.podWriter.Flush()
}

func (m *KubernetesMonitor) writeNodeMetrics(nodes []corev1.Node, timestamp string) (int64, int64) {
	var totalCPU, totalMem int64

	for _, node := range nodes {
		nodeCPU := node.Status.Capacity.Cpu().MilliValue()
		nodeMem := node.Status.Capacity.Memory().Value()
		totalCPU += nodeCPU
		totalMem += nodeMem

		m.nodeWriter.Write([]string{
			timestamp,
			string(node.UID),
			strconv.FormatInt(nodeCPU, 10),
			strconv.FormatInt(nodeMem, 10),
			node.Labels["cluster"],
		})
	}
	m.nodeWriter.Flush()
	return totalCPU, totalMem
}

func (m *KubernetesMonitor) writeClusterMetrics(pods []corev1.Pod, totalCPU, totalMem int64, timestamp string) {
	var allocatedCPU, allocatedMem int64

	for _, pod := range pods {
		for _, container := range pod.Spec.Containers {
			allocatedCPU += container.Resources.Requests.Cpu().MilliValue()
			allocatedMem += container.Resources.Requests.Memory().Value()
		}
	}

	cpuUtilization := float64(allocatedCPU) / float64(totalCPU) * 100
	memUtilization := float64(allocatedMem) / float64(totalMem) * 100

	m.clusterWriter.Write([]string{
		timestamp,
		"cluster-1",
		strconv.FormatInt(totalCPU, 10),
		strconv.FormatInt(totalMem, 10),
		strconv.FormatInt(allocatedCPU, 10),
		strconv.FormatInt(allocatedMem, 10),
		strconv.FormatFloat(cpuUtilization, 'f', 2, 64),
		strconv.FormatFloat(memUtilization, 'f', 2, 64),
	})
	m.clusterWriter.Flush()
}
