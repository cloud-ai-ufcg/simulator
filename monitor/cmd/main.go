package main

import (
	"context"
	"log"

	"monitor/pkg/monitor"
)

func main() {
	k8sMonitor, err := monitor.NewKubernetesMonitor()
	if err != nil {
		log.Fatalf("Failed to create Kubernetes monitor: %v", err)
	}
	defer k8sMonitor.Close()

	ctx := context.Background()
	k8sMonitor.CollectMetrics(ctx)
}
