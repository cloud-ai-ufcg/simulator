package main

import (
	"os"
	"path/filepath"
	"simulator/internal/aiengine"
	"simulator/internal/analyzer"
	"simulator/internal/baseline"
	"simulator/internal/broker"
	"simulator/internal/config"
	"simulator/internal/constants"
	"simulator/internal/log"
	"simulator/internal/utils"
	"sync"
	"time"
)

func main() {
	log.Println(constants.SimulatorLogo)

	log.Infof("Starting sequential operation cycle...")

	enabled, err := config.LoadAIEngineEnabled("../data/config.yaml")
	if err != nil {
		log.Errorf("Erro ao ler config.yaml: %v", err)
		os.Exit(1)
	}
	inputFilePath := "../data/input.json"

	// Baseline-only safety net: samples ResourceBindings stuck Scheduled=False
	// every 30s while the simulation runs, written into the run directory
	// alongside metrics.json once it exists (see below). Nil (and never
	// started) for AI-driven runs, matching analyzer/data_loader.py's
	// handling of a missing unschedulable_bindings.jsonl as "not applicable".
	var unschedulablePoller *baseline.UnschedulablePoller
	if config.IsAIDisabledByEnv() {
		unschedulablePoller = baseline.NewUnschedulablePoller(30 * time.Second)
		unschedulablePoller.Start()
	}

	var wg sync.WaitGroup
	var brokerErr error

	if enabled {
		wg.Add(1)
		go func() {
			defer wg.Done()
			if err := aiengine.CallAIEngineAPI(true); err != nil {
				log.Errorf("Error calling AI-Engine API: %v", err)
			}
		}()
	}

	wg.Add(1)
	go func() {
		defer wg.Done()
		if err := broker.CallBrokerAPI(inputFilePath); err != nil {
			log.Errorf("Error calling Broker API: %v", err)
			brokerErr = err
		}

		if enabled {
			if err := aiengine.CallAIEngineAPI(false); err != nil {
				log.Errorf("Error calling AI-Engine STOP API: %v", err)
			}
		}
	}()

	wg.Wait()
	if unschedulablePoller != nil {
		unschedulablePoller.Stop()
	}
	if brokerErr != nil {
		os.Exit(1)
	}

	// Save container logs and metrics (this creates the run directory)
	runDir := utils.SaveContainerLogs()
	if runDir == "" {
		log.Errorf("Failed to save container logs")
		os.Exit(1)
	}

	// Save metrics to the run directory
	if err := analyzer.SaveMetrics(runDir); err != nil {
		log.Errorf("Failed to save metrics: %v", err)
		os.Exit(1)
	}

	if unschedulablePoller != nil {
		unschedFile := filepath.Join(runDir, "unschedulable_bindings.jsonl")
		if err := unschedulablePoller.WriteJSONL(unschedFile); err != nil {
			log.Errorf("Failed to write unschedulable_bindings.jsonl: %v", err)
		}
	}

	if err := analyzer.GeneratePlots(runDir); err != nil {
		log.Errorf("Failed to generate plots: %v", err)
	}

	// Convert to absolute path for display
	absRunDir, err := filepath.Abs(runDir)
	if err != nil {
		absRunDir = runDir
	}


	log.Infof("Sequential execution cycle finished.")
	log.Infof("Simulation data saved to: %s", absRunDir)

}
