package model

type Resources struct {
	CPU    string `json:"cpu"`
	Memory string `json:"memory"`
}

type Workload struct {
	WorkloadID     string    `json:"workload_id"`
	Kind           string    `json:"kind"`
	Resources      Resources `json:"resources"`
	PodsTotal      int       `json:"pods_total"`
	PodsPending    int       `json:"pods_pending"`
	PercentPending float64   `json:"percent_pending"`
	ClusterLabel   string    `json:"cluster_label"`
}

type ClusterLoad struct {
	CPU    float64 `json:"cpu"`
	Memory float64 `json:"memory"`
}

type ClusterInfo struct {
	ClusterLabel          string      `json:"cluster_label"`
	ClusterLoad           ClusterLoad `json:"cluster_load"`
	ClusterCPUCapacity    string      `json:"cluster_cpu_capacity"`
	ClusterMemoryCapacity string      `json:"cluster_memory_capacity"`
}

type MetricsOutput struct {
	Workloads   []Workload    `json:"workloads"`
	ClusterInfo []ClusterInfo `json:"cluster_info"`
}
