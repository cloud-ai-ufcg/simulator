package api

import (
	"bytes"
	"encoding/csv"
	"encoding/json"
	"fmt"
	"io"
	"io/ioutil"
	"net/http"
	"os"
	"strconv"
	"time"

	"simulator/constants"
)

// CallBrokerAPI sends a POST request to the Broker API.
func CallBrokerAPI(inputFilePath string, apiURL string) error {
	fmt.Printf("Calling Broker API at %s with file %s...\n", apiURL, inputFilePath)

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

	fmt.Println("Broker API called successfully.")
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

// ActuatorRecommendation represents a recommendation to be sent to the Actuator API
type ActuatorRecommendation struct {
	WorkloadID string `json:"workload_id"` // string
	Label      int    `json:"label"`       // int
	Kind       string `json:"kind"`        // string
}

// ConvertCSVToJSON reads a recommendations CSV file and returns a JSON ready to be sent
func ConvertCSVToJSON(csvFilePath string) ([]byte, error) {
	// Open CSV file
	file, err := os.Open(csvFilePath)
	if err != nil {
		return nil, fmt.Errorf("error opening recommendations file: %w", err)
	}
	defer file.Close()

	reader := csv.NewReader(file)

	// Read header and map column indices
	header, err := reader.Read()
	if err != nil {
		return nil, fmt.Errorf("error reading CSV header: %w", err)
	}
	colIdx := map[string]int{}
	for i, col := range header {
		colIdx[col] = i
	}
	required := []string{"workload_id", "label", "kind"}
	for _, col := range required {
		if _, ok := colIdx[col]; !ok {
			return nil, fmt.Errorf("required column '%s' not found in CSV header", col)
		}
	}

	var recommendations []ActuatorRecommendation

	// Read records
	for {
		record, err := reader.Read()
		if err == io.EOF {
			break
		}
		if err != nil {
			return nil, fmt.Errorf("error reading CSV record: %w", err)
		}

		// Check if there are enough columns
		if len(record) < len(header) {
			return nil, fmt.Errorf("invalid CSV record: expected at least %d columns, got %d", len(header), len(record))
		}

		// Get values by dynamic positions
		workloadID := record[colIdx["workload_id"]]
		labelStr := record[colIdx["label"]]
		kind := record[colIdx["kind"]]

		// Convert label to integer
		label, err := strconv.Atoi(labelStr)
		if err != nil {
			return nil, fmt.Errorf("error converting label '%s' to integer on line: %w", labelStr, err)
		}

		// Add namespace to workload_id if not present
		if len(workloadID) > 0 && !containsSlash(workloadID) {
			workloadID = "default/" + workloadID
		}

		recommendations = append(recommendations, ActuatorRecommendation{
			WorkloadID: workloadID,
			Label:      label,
			Kind:       kind,
		})
	}

	// Convert to JSON
	jsonData, err := json.Marshal(recommendations)
	if err != nil {
		return nil, fmt.Errorf("error converting to JSON: %w", err)
	}

	return jsonData, nil
}

// CallActuatorAPI reads the recommendations CSV file and sends it to the /apply endpoint of the Actuator API
func CallActuatorAPI(recommendationsFilePath string, apiURL string) error {
	fmt.Printf("Calling Actuator API at %s with file %s...\n", apiURL, recommendationsFilePath)

	// Convert CSV to JSON
	jsonData, err := ConvertCSVToJSON(recommendationsFilePath)
	if err != nil {
		return fmt.Errorf("error converting CSV to JSON: %w", err)
	}

	// Create POST request
	req, err := http.NewRequest("POST", apiURL+"apply", bytes.NewBuffer(jsonData))
	if err != nil {
		return fmt.Errorf("error creating HTTP request: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")

	// Send request
	client := &http.Client{Timeout: 30 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return fmt.Errorf("error sending request: %w", err)
	}
	defer resp.Body.Close()

	// Read response
	body, err := ioutil.ReadAll(resp.Body)
	if err != nil {
		return fmt.Errorf("error reading response: %w", err)
	}

	// Check response status
	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("API returned error %d: %s", resp.StatusCode, string(body))
	}

	fmt.Printf("Actuator API called successfully. Response: %s\n", string(body))
	return nil
}

// Helper function to check if the string contains a slash (/)
func containsSlash(s string) bool {
	for _, c := range s {
		if c == '/' {
			return true
		}
	}
	return false
}
