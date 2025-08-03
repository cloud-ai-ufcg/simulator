package main

import (
	"os"
	"simulator/internal/aiengine"
	"simulator/internal/avaliator"
	"simulator/internal/broker"
	"simulator/internal/constants"
	"simulator/internal/log"
	"simulator/internal/utils"
	"sync"
)

func main() {
	log.Println(constants.SimulatorLogo)

	log.Infof("Starting sequential operation cycle...")

	aiEngineFlag := os.Getenv("AI_ENGINE")
	inputFilePath := "../data/input.json"

	var wg sync.WaitGroup
	var brokerErr error

	if aiEngineFlag == "ON" {
		wg.Add(1)
		go func() {
			defer wg.Done()
			if err := aiengine.CallAIEngineAPI(aiEngineFlag); err != nil {
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

		if aiEngineFlag == "ON" {
			if err := aiengine.CallAIEngineAPI("OFF"); err != nil {
				log.Errorf("Error calling AI-Engine STOP API: %v", err)
			}
		}
	}()

	wg.Wait()
	if brokerErr != nil {
		os.Exit(1)
	}

	utils.SaveContainerLogs()

	avaliator.CallAvaliatorAndProcess()

	log.Infof("Sequential execution cycle finished.")
}
