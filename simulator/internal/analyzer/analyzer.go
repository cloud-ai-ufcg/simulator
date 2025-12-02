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

// SaveMetrics fetches metrics from Monitor API and saves to the run directory
func SaveMetrics(runDir string) error {
	log.Infof("Fetching metrics from %s...", constants.MetricsURL)

	resp, err := http.Get(constants.MetricsURL)
	if err != nil {
		return fmt.Errorf("error calling metrics API: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("metrics API returned status code: %d", resp.StatusCode)
	}

	body, err := ioutil.ReadAll(resp.Body)
	if err != nil {
		return fmt.Errorf("error reading metrics response: %w", err)
	}

	// Save metrics.json in the run directory
	metricsFile := filepath.Join(runDir, "metrics.json")
	if err := ioutil.WriteFile(metricsFile, body, 0644); err != nil {
		return fmt.Errorf("error writing metrics.json: %w", err)
	}

	log.Infof("Metrics saved to %s", metricsFile)
	return nil
}

// CallAnalyzerAndProcess runs the analyzer to generate plots and summaries
// This function is kept for backward compatibility but can be called separately
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

	// Get the current run timestamp (already created by SaveContainerLogs)
	timestamp := utils.GetOrCreateRunTimestamp()
	runDir := filepath.Join(constants.OutputDir, timestamp)

	// Ensure run directory exists (should already be created by SaveContainerLogs)
	if err := os.MkdirAll(runDir, 0755); err != nil {
		log.Errorf("Error ensuring run directory exists: %v", err)
		return
	}

	// Save metrics.json in the run directory
	metricsFile := filepath.Join(runDir, "metrics.json")
	err = ioutil.WriteFile(metricsFile, body, 0644)
	if err != nil {
		log.Errorf("Error writing metrics.json: %v", err)
		return
	}

	log.Infof("Metrics saved to %s", metricsFile)

	// Convert to absolute path for the Makefile
	absRunDir, err := filepath.Abs(runDir)
	if err != nil {
		log.Errorf("Error getting absolute path: %v", err)
		return
	}

	// Run the analyzer using make with the run directory
	log.Infof("Running analyzer using Makefile...")
	cmd := exec.Command(
		"make",
		"-C",
		"../../analyzer",
		"generate-plots",
		fmt.Sprintf("RUN_DIR=%s", absRunDir),
	)
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr

	log.Infof("Running metrics analysis and generating visualizations using analyzer Makefile...")
	if err := cmd.Run(); err != nil {
		log.Errorf("Error running analyzer: %v", err)
		return
	}

	log.Infof("Finished generating visualizations. Results saved in analyzer/output/%s/", timestamp)
}
