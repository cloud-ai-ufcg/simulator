package utils

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"simulator/internal/constants"
)

// SaveContainerLogs creates the logs directory and saves logs from all relevant containers.
func SaveContainerLogs() {
	logsDir := constants.LogsDir
	if err := os.MkdirAll(logsDir, 0755); err != nil {
		fmt.Fprintf(os.Stderr, "Error creating logs directory: %v\n", err)
	}
	containerLogs := map[string]string{
		constants.ContainerActuator: filepath.Join(logsDir, "actuator.log"),
		constants.ContainerBroker:   filepath.Join(logsDir, "broker.log"),
		constants.ContainerMonitor:  filepath.Join(logsDir, "monitor.log"),
		constants.ContainerAIEngine: filepath.Join(logsDir, "ai-engine.log"),
	}
	for container, logFile := range containerLogs {
		cmd := exec.Command("docker", "logs", container)
		logData, err := cmd.CombinedOutput()
		if err != nil {
			fmt.Fprintf(os.Stderr, "Error collecting logs from container %s: %v\n", container, err)
			continue
		}
		err = os.WriteFile(logFile, logData, 0644)
		if err != nil {
			fmt.Fprintf(os.Stderr, "Error saving logs from container %s to %s: %v\n", container, logFile, err)
		}
	}
}
