package broker

import (
	"bytes"
	"fmt"
	"io/ioutil"
	"net/http"
	"os"
	"simulator/internal/constants"
	"simulator/internal/log"
)

// CallBrokerAPI reads a JSON file and sends its content to the Broker API.
func CallBrokerAPI(inputFilePath string) error {
	apiURL := constants.APIURLBroker
	log.Infof("Calling Broker API at %s with file %s...", apiURL, inputFilePath)

	jsonFile, err := os.Open(inputFilePath)
	if err != nil {
		return fmt.Errorf("error opening JSON file: %w", err)
	}
	defer jsonFile.Close()

	byteValue, err := ioutil.ReadAll(jsonFile)
	if err != nil {
		return fmt.Errorf("error reading JSON file: %w", err)
	}

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

	log.Infof("Broker API called successfully.")
	return nil
}
