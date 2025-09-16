package main

import (
	"os"
	"simulator/internal/aiengine"
	"simulator/internal/analyzer"
	"simulator/internal/broker"
	"simulator/internal/config"
	"simulator/internal/constants"
	"simulator/internal/log"
	"simulator/internal/utils"
	"sync"
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
	if brokerErr != nil {
		os.Exit(1)
	}

	utils.SaveContainerLogs()

	analyzer.CallAnalyzerAndProcess()

	log.Infof("Sequential execution cycle finished.")
}
