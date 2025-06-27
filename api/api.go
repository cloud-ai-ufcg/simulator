package api

import (
	"bytes"
	"fmt"
	"io"
	"io/ioutil"
	"net/http"
	"time"

	"simulator/constants"
)

// CallBrokerAPI sends a POST request to the Broker API.
func CallBrokerAPI(inputFilePath string, apiURL string) error {
	fmt.Printf("%s%s%s: %sCalling Broker API at %s%s%s with file %s%s%s...%s\n",
		constants.ColorCyan, constants.LogPrefixBroker, constants.ColorReset,
		constants.ColorBlue, constants.ColorPurple, apiURL, constants.ColorBlue,
		constants.ColorPurple, inputFilePath, constants.ColorBlue, constants.ColorReset)

	// Read the input JSON file
	inputData, err := ioutil.ReadFile(inputFilePath)
	if err != nil {
		return fmt.Errorf("error reading input file %s: %w", inputFilePath, err)
	}

	// Create the HTTP request
	req, err := http.NewRequest("POST", apiURL, bytes.NewBuffer(inputData))
	if err != nil {
		return fmt.Errorf("error creating HTTP request: %w", err)
	}

	// Set the headers
	req.Header.Set("Content-Type", "application/json")

	// Send the request
	client := &http.Client{Timeout: 30 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return fmt.Errorf("error sending request to Broker API: %w", err)
	}
	defer resp.Body.Close()

	// Check the response status
	if resp.StatusCode != http.StatusOK {
		body, _ := ioutil.ReadAll(resp.Body)
		return fmt.Errorf("API returned status %d: %s", resp.StatusCode, string(body))
	}

	fmt.Printf("%s%s%s: %sBroker API called successfully.%s\n",
		constants.ColorCyan, constants.LogPrefixBroker, constants.ColorReset, constants.ColorGreen, constants.ColorReset)
	return nil
}

// CallAIEngineAPI sends a POST request to the AI-Engine API to start the process.
func CallAIEngineAPI(apiURL string) error {
	fmt.Printf("%s%s%s: %sStarting AI-Engine via API at %s%s%s...%s\n",
		constants.ColorCyan, constants.LogPrefixAIEngine, constants.ColorReset, constants.ColorBlue, constants.ColorPurple, apiURL, constants.ColorBlue, constants.ColorReset)

	// Using POST as it triggers an action. We assume there is no request body.
	resp, err := http.Post(apiURL, "application/json", nil)
	if err != nil {
		return fmt.Errorf("failed to make request to AI-Engine API: %w", err)
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return fmt.Errorf("failed to read response from AI-Engine API: %w", err)
	}

	if resp.StatusCode >= 400 {
		return fmt.Errorf("AI-Engine API returned error status %d: %s", resp.StatusCode, string(body))
	}

	fmt.Printf("%s%s%s: %sAI-Engine API responded successfully.%s\n",
		constants.ColorCyan, constants.LogPrefixAIEngine, constants.ColorReset, constants.ColorGreen, constants.ColorReset)
	fmt.Printf("%s%s%s: %sResponse: %s%s\n",
		constants.ColorCyan, constants.LogPrefixAIEngine, constants.ColorReset, constants.ColorGreen, string(body), constants.ColorReset)

	return nil
}
