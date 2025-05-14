package models

// PodMetrics represents metrics collected from a Kubernetes pod
type PodMetrics struct {
	ID            string
	Status        string
	Node          string
	Cluster       string
	RequestedCPU  string
	RequestedMem  string
	Timestamp     string
}

// NodeMetrics represents metrics collected from a Kubernetes node
type NodeMetrics struct {
	ID          string
	TotalCPU    string
	TotalMemory string
	Cluster     string
	Timestamp   string
}

// ClusterMetrics represents aggregated metrics for the entire cluster
type ClusterMetrics struct {
	ID                 string
	TotalCPU          int64
	TotalMemory       int64
	AllocatedCPU      int64
	AllocatedMemory   int64
	CPUUtilization    float64
	MemoryUtilization float64
	Timestamp         string
} 