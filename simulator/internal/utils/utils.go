package utils

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"simulator/internal/constants"
	"time"
)

var currentRunTimestamp string

// GetOrCreateRunTimestamp returns the current run timestamp, creating it if it doesn't exist
func GetOrCreateRunTimestamp() string {
	if currentRunTimestamp == "" {
		currentRunTimestamp = GetTimestamp()
	}
	return currentRunTimestamp
}

// SaveContainerLogs creates the logs directory and saves logs from all relevant containers.
func SaveContainerLogs() string {
	timestamp := GetOrCreateRunTimestamp()
	runDir := filepath.Join(constants.OutputDir, timestamp)
	logsDir := filepath.Join(runDir, "logs")

	if err := os.MkdirAll(logsDir, 0755); err != nil {
		fmt.Fprintf(os.Stderr, "Error creating logs directory: %v\n", err)
		return ""
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

	kubectlLogFile := filepath.Join(logsDir, "kubectl.log")
	kubeconfigPath := filepath.Join(os.Getenv("HOME"), ".kube/members.config")
	kubectlCmd := exec.Command("kubectl", "get", "nodes", "--namespace=default", "--context=member2", "--kubeconfig="+kubeconfigPath)
	kubectlLogData, err := kubectlCmd.CombinedOutput()
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error collecting logs from kubectl: %v\n", err)
	} else {
		err = os.WriteFile(kubectlLogFile, kubectlLogData, 0644)
		if err != nil {
			fmt.Fprintf(os.Stderr, "Error saving kubectl logs to %s: %v\n", kubectlLogFile, err)
		}
	}

	return runDir
}

// GetTimestamp returns a string with the current date and time in YYYYMMDD_HHMMSS format
func GetTimestamp() string {
	return time.Now().Format("20060102_150405")
}
