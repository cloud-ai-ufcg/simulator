package utils

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"simulator/internal/constants"
	"time"
)

// SaveContainerLogs creates the logs directory and saves logs from all relevant containers.
func SaveContainerLogs() {
	logsDir := constants.LogsDir
	if err := os.MkdirAll(logsDir, 0755); err != nil {
		fmt.Fprintf(os.Stderr, "Error creating logs directory: %v\n", err)
	}
	timestamp := GetTimestamp()
	containerLogs := map[string]string{
		constants.ContainerActuator: filepath.Join(logsDir, fmt.Sprintf("actuator_%s.log", timestamp)),
		constants.ContainerBroker:   filepath.Join(logsDir, fmt.Sprintf("broker_%s.log", timestamp)),
		constants.ContainerMonitor:  filepath.Join(logsDir, fmt.Sprintf("monitor_%s.log", timestamp)),
		constants.ContainerAIEngine: filepath.Join(logsDir, fmt.Sprintf("ai-engine_%s.log", timestamp)),
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

	kubectlLogFile := filepath.Join(logsDir, fmt.Sprintf("kubectl_%s.log", timestamp))
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
}

// GetTimestamp returns a string with the current date and time in YYYYMMDD_HHMMSS format
func GetTimestamp() string {
	return time.Now().Format("20060102_150405")
}
