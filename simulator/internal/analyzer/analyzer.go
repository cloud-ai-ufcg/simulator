package analyzer

import (
	"fmt"
	"io"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"simulator/internal/constants"
	"simulator/internal/log"
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

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return fmt.Errorf("error reading metrics response: %w", err)
	}

	// Save metrics.json in the run directory
	metricsFile := filepath.Join(runDir, "metrics.json")
	if err := os.WriteFile(metricsFile, body, 0644); err != nil {
		return fmt.Errorf("error writing metrics.json: %w", err)
	}

	log.Infof("Metrics saved to %s", metricsFile)
	return nil
}

// GeneratePlots runs the analyzer Makefile to generate plots and summaries
// for the given run directory (expects metrics.json to already be there)
func GeneratePlots(runDir string) error {
	absRunDir, err := filepath.Abs(runDir)
	if err != nil {
		return fmt.Errorf("error getting absolute path: %w", err)
	}

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

	if err := cmd.Run(); err != nil {
		return fmt.Errorf("error running analyzer: %w", err)
	}

	log.Infof("Finished generating visualizations. Results saved in %s/plots/", absRunDir)
	return nil
}
