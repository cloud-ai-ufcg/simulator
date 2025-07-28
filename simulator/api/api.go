package api

import (
	"bytes"
	"fmt"
	"io/ioutil"
	"net/http"
	"os"
	"time"
	"simulator/constants"
)

// CallBrokerAPI reads a JSON file and sends its content to the Broker API.
func CallBrokerAPI(inputFilePath, apiURL string) error {
	fmt.Printf("%s%s%s: %sCalling Broker API at %s%s%s with file %s%s%s...%s\n",
		constants.ColorCyan, constants.LogPrefixBroker, constants.ColorReset,
		constants.ColorBlue, constants.ColorPurple, apiURL, constants.ColorBlue,
		constants.ColorPurple, inputFilePath, constants.ColorBlue, constants.ColorReset)

	jsonFile, err := os.Open(inputFilePath)
	if err != nil {
		return fmt.Errorf("error opening JSON file: %w", err)
	}
	defer jsonFile.Close()

	byteValue, err := ioutil.ReadAll(jsonFile)
	if err != nil {
		return fmt.Errorf("error reading JSON file: %w", err)
	}

	// Create a custom HTTP client with no timeout
	client := &http.Client{
		Timeout: 0,
	}

	req, err := http.NewRequest("POST", apiURL, bytes.NewBuffer(byteValue))
	if err != nil {
		return fmt.Errorf("error creating request for Broker API: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")

	resp, err := client.Do(req)
	if err != nil {
		return fmt.Errorf("error sending request to Broker API: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK && resp.StatusCode != http.StatusAccepted {
		body, _ := ioutil.ReadAll(resp.Body)
		return fmt.Errorf("broker API returned non-OK status: %s, body: %s", resp.Status, string(body))
	}

	fmt.Printf("%s%s%s: %sBroker API called successfully.%s\n",
		constants.ColorCyan, constants.LogPrefixBroker, constants.ColorReset, constants.ColorGreen, constants.ColorReset)
	return nil
}

// CallAIEngineAPI sends a request to the AI Engine API, retrying up to 10 times on failure.
func CallAIEngineAPI(apiURL string) error {
	client := &http.Client{
		Timeout: 0,
	}

	const maxRetries = 10
	var lastErr error

	for i := 0; i < maxRetries; i++ {
		// Use POST instead of GET
		resp, err := client.Post(apiURL, "application/json", nil)
		if err != nil {
			lastErr = err
			fmt.Fprintf(os.Stderr, "%s%s%s: %sError calling AI-Engine API (attempt %d/%d): %v. Retrying in 5 seconds...%s\n",
				constants.ColorCyan, constants.LogPrefixAIEngine, constants.ColorReset,
				constants.ColorRed, i+1, maxRetries, err, constants.ColorReset)
			time.Sleep(5 * time.Second)
			continue
		}

		if resp.StatusCode == http.StatusOK {
			resp.Body.Close()
			fmt.Printf("%s%s%s: %sAI-Engine API called successfully.%s\n",
				constants.ColorCyan, constants.LogPrefixAIEngine, constants.ColorReset, constants.ColorGreen, constants.ColorReset)
			return nil
		}

		body, _ := ioutil.ReadAll(resp.Body)
		resp.Body.Close()
		lastErr = fmt.Errorf("ai-engine API returned non-OK status: %s, body: %s", resp.Status, string(body))
		fmt.Fprintf(os.Stderr, "%s%s%s: %s%v (attempt %d/%d). Retrying in 5 seconds...%s\n",
			constants.ColorCyan, constants.LogPrefixAIEngine, constants.ColorReset,
			constants.ColorRed, lastErr, i+1, maxRetries, constants.ColorReset)

		time.Sleep(5 * time.Second)
	}

	return fmt.Errorf("failed to call AI-Engine API after %d attempts: %w", maxRetries, lastErr)
}
