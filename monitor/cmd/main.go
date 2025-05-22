package main

import (
	"log"
	"time"

	"monitor/internal/collector"
	"monitor/internal/config"
	"monitor/internal/writer"
)

func main() {
	// Load configuration
	cfg, err := config.LoadConfig()
	if err != nil {
		log.Fatalf("Failed to load configuration: %v", err)
	}

	// Initialize collector
	collector := collector.NewCollector(cfg)

	// Initialize writer
	writer := writer.NewWriter("monitor_outputs.json")

	// Start monitoring loop
	ticker := time.NewTicker(3 * time.Second)
	defer ticker.Stop()

	for {
		select {
		case <-ticker.C:
			// Collect metrics from both clusters
			metrics, err := collector.CollectMetrics()
			if err != nil {
				log.Printf("Error collecting metrics: %v", err)
				continue
			}

			// Write metrics to file
			if err := writer.WriteMetrics(metrics); err != nil {
				log.Printf("Error writing metrics: %v", err)
			}
		}
	}
}
