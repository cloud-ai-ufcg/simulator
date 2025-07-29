package main

import (
	"fmt"
	"os"
	"simulator/internal/aiengine"
	"simulator/internal/avaliator"
	"simulator/internal/broker"
	"simulator/internal/constants"
	"simulator/internal/utils"
	"sync"
)

func main() {
	fmt.Println(constants.SimulatorLogo)

	fmt.Printf("%s%s%s: %sStarting sequential operation cycle...%s\n",
		constants.ColorCyan, constants.LogPrefixSimulator, constants.ColorReset, constants.ColorBlue, constants.ColorReset)
	fmt.Println("")

	aiEngineFlag := os.Getenv("AI_ENGINE")
	inputFilePath := "../data/input.json"

	var wg sync.WaitGroup
	var brokerErr error

	if aiEngineFlag == "ON" {
		wg.Add(1)
		go func() {
			defer wg.Done()
			if err := aiengine.CallAIEngineAPI(aiEngineFlag); err != nil {
				fmt.Fprintf(os.Stderr, "%s%s%s: %sError calling AI-Engine API: %v%s\n", constants.ColorCyan, constants.LogPrefixAIEngine, constants.ColorReset, constants.ColorRed, err, constants.ColorReset)
			}
		}()
	}

	wg.Add(1)
	go func() {
		defer wg.Done()
		if err := broker.CallBrokerAPI(inputFilePath); err != nil {
			fmt.Fprintf(os.Stderr, "%s%s%s: %sError calling Broker API: %v%s\n", constants.ColorCyan, constants.LogPrefixBroker, constants.ColorReset, constants.ColorRed, err, constants.ColorReset)
			brokerErr = err
		}

		if aiEngineFlag == "ON" {
			if err := aiengine.CallAIEngineAPI("OFF"); err != nil {
				fmt.Fprintf(os.Stderr, "%s%s%s: %sError calling AI-Engine STOP API: %v%s\n", constants.ColorCyan, constants.LogPrefixAIEngine, constants.ColorReset, constants.ColorRed, err, constants.ColorReset)
			}
		}
	}()

	wg.Wait()
	if brokerErr != nil {
		os.Exit(1)
	}

	avaliator.CallAvaliatorAndProcess()

	utils.SaveContainerLogs()

	fmt.Printf("\n%s%s%s: %sAll operations completed successfully.%s\n",
		constants.ColorCyan, constants.LogPrefixSimulator, constants.ColorReset, constants.ColorGreen, constants.ColorReset)
	fmt.Printf("%s%s%s: %sSequential execution cycle finished.%s\n",
		constants.ColorCyan, constants.LogPrefixSimulator, constants.ColorReset, constants.ColorGreen, constants.ColorReset)
}
