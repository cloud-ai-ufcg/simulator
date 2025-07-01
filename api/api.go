package api

import (
	"bytes"
	"fmt"
	"io/ioutil"
	"net/http"
	"os"

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

// CallAIEngineAPI sends a request to the AI Engine API.
func CallAIEngineAPI(apiURL string) error {
	client := &http.Client{
		Timeout: 0,
	}
	// Use POST instead of GET
	resp, err := client.Post(apiURL, "application/json", nil)
	if err != nil {
		return fmt.Errorf("error sending request to AI-Engine API: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		body, _ := ioutil.ReadAll(resp.Body)
		return fmt.Errorf("ai-engine API returned non-OK status: %s, body: %s", resp.Status, string(body))
	}

	fmt.Println("Successfully called AI-Engine API.")
	return nil
}
