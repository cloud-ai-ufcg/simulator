package main

import (
	"fmt"
	"log"
	"os"
	"time"

	"github.com/cloud-ai-ufcg/broker/broker" // Corrected import path
)

func monitor() {
	for {
		fmt.Println("Monitor is running...")
		time.Sleep(5 * time.Second)
	}
}

func main() {
	// Placeholder paths for broker configuration
	// TODO: Replace these with actual paths to your CSV and YAML files
	csv_path := "example_configs/events.csv"   // Using local example CSV
	yaml_path := "example_configs/config.yaml" // Using local example YAML

	config_yaml, err := os.Open(yaml_path)
	if err != nil {
		log.Fatalf("Failed to open YAML config %s: %v", yaml_path, err)
	}
	defer config_yaml.Close()

	csv_data, err := os.Open(csv_path)
	if err != nil {
		log.Fatalf("Failed to open CSV data %s: %v", csv_path, err)
	}
	defer csv_data.Close()

	// Launch broker in a goroutine
	go broker.Run(csv_data, config_yaml)

	// Launch monitor in a goroutine
	go monitor()

	// Keep the main goroutine alive
	// This is a simple way; you might want more sophisticated handling
	// for clean shutdown in a real application.
	fmt.Println("Simulator started. Broker and Monitor are running in the background.")
	select {}
}
