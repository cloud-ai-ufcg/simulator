package analyzer

import (
	"fmt"
	"io/ioutil"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"simulator/internal/constants"
	"simulator/internal/log"
	"simulator/internal/utils"
)

func CallAnalyzerAndProcess() {
	log.Infof("Calling metrics endpoint at %s...", constants.MetricsURL)

	resp, err := http.Get(constants.MetricsURL)
	if err != nil {
		log.Errorf("Error calling metrics API: %v", err)
		return
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		log.Errorf("Metrics API returned non-200 status code: %d", resp.StatusCode)
		return
	}

	body, err := ioutil.ReadAll(resp.Body)
	if err != nil {
		log.Errorf("Error reading metrics response body: %v", err)
		return
	}

	// Ensure dataplots directory exists
	dataplotsDir := constants.DataplotsDir
	if err := os.MkdirAll(dataplotsDir, 0755); err != nil {
		log.Errorf("Error creating dataplots directory: %v", err)
		return
	}
	// Save metrics as metrics.json (always overwrite)
	dataplotsFile := filepath.Join(dataplotsDir, "metrics.json")
	err = ioutil.WriteFile(dataplotsFile, body, 0644)
	if err != nil {
		log.Errorf("Error writing metrics.json in dataplots: %v", err)
		return
	}

	// Ensure output/metrics directory exists
	outputMetricsDir := "../../simulator/data/output/metrics"
	if err := os.MkdirAll(outputMetricsDir, 0755); err != nil {
		log.Errorf("Error creating output/metrics directory: %v", err)
		return
	}
	timestamp := utils.GetTimestamp()
	outputMetricsFile := filepath.Join(outputMetricsDir, fmt.Sprintf("metrics_%s.json", timestamp))
	err = ioutil.WriteFile(outputMetricsFile, body, 0644)
	if err != nil {
		log.Errorf("Error writing metrics file in output/metrics: %v", err)
		return
	}

	// 3. Run the main evaluator script
	cmd := exec.Command(
		constants.PythonExecutable,
		"../../analyzer/main.py",
		dataplotsFile,
	)
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr

	log.Infof("Running metrics analysis and generating visualizations...")
	if err := cmd.Run(); err != nil {
		log.Errorf("Error running evaluator: %v", err)
		return
	}

	log.Infof("Finished generating visualizations.")
}
