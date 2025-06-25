package main

import (
	"fmt"
	"os"
	"sync"

	"simulator/api"
	"simulator/constants"
	"simulator/utils"
)

func main() {
	fmt.Println("")

	outputDir := "data/output"
	// Ensures the directory exists before cleaning
	if _, err := os.Stat(outputDir); os.IsNotExist(err) {
		if err := os.MkdirAll(outputDir, 0755); err != nil {
			fmt.Fprintf(os.Stderr, "Error creating output directory: %v\n", err)
			os.Exit(1)
		}
	}
	if err := utils.ClearOutputDir(outputDir); err != nil {
		fmt.Fprintf(os.Stderr, "Error cleaning output directory: %v\n", err)
		os.Exit(1)
	}

	fmt.Println("Starting parallel operation cycle...")

	var wg sync.WaitGroup
	engineErrChan := make(chan error, 1)

	wg.Add(2)

	// 1. Broker via API
	go func() {
		defer wg.Done()
		apiURL := "http://localhost:8080/broker/"
		inputFilePath := "data/input_json.json" // Relative to the project root
		if err := api.CallBrokerAPI(inputFilePath, apiURL); err != nil {
			fmt.Fprintf(os.Stderr, "%s%s%s: Error calling Broker API: %v%s\n", constants.ColorCyan, constants.LogPrefixBroker, constants.ColorReset, err, constants.ColorReset)
		} else {
			fmt.Printf("%s%s%s: Broker finished successfully via API.%s\n", constants.ColorCyan, constants.LogPrefixBroker, constants.ColorReset, constants.ColorReset)
		}
	}()

	// 2. AI Engine via API
	go func() {
		defer wg.Done()
		defer close(engineErrChan)

		// The AI-Engine API URL. Adjust if necessary.
		aiEngineAPIURL := "http://0.0.0.0:8083/start"
		if err := api.CallAIEngineAPI(aiEngineAPIURL); err != nil {
			engineErrChan <- err
		}
	}()

	wg.Wait()

	// Finalization and channel error handling
	fmt.Println("\n--- Final Operation Status ---")

	// AI Engine
	select {
	case err, ok := <-engineErrChan:
		if ok && err != nil {
			fmt.Fprintf(os.Stderr, "%s%s%s: Error: %v%s\n", constants.ColorCyan, constants.LogPrefixAIEngine, constants.ColorReset, err, constants.ColorReset)
		} else if ok {
			fmt.Printf("%s%s%s: Completed successfully.%s\n", constants.ColorCyan, constants.LogPrefixAIEngine, constants.ColorReset, constants.ColorReset)
		} else {
			fmt.Printf("%s%s%s: Channel closed without explicit error.%s\n", constants.ColorCyan, constants.LogPrefixAIEngine, constants.ColorReset, constants.ColorReset)
		}
	default:
		fmt.Printf("%s%s%s: Completed (check logs for details).%s\n", constants.ColorCyan, constants.LogPrefixAIEngine, constants.ColorReset, constants.ColorReset)
	}

	fmt.Println("\nParallel execution cycle finished.")
}
