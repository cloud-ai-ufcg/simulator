package avaliator

import (
	"fmt"
	"io/ioutil"
	"net/http"
	"os"
	"os/exec"
	"simulator/internal/constants"
)

func CallAvaliatorAndProcess() {
	fmt.Printf("%s%s%s: %sCalling metrics endpoint at %s...%s\n",
		constants.ColorCyan, constants.LogPrefixSimulator, constants.ColorReset, constants.ColorBlue, constants.MetricsURL, constants.ColorReset)

	resp, err := http.Get(constants.MetricsURL)
	if err != nil {
		fmt.Fprintf(os.Stderr, "%s%s%s: %sError calling metrics API: %v%s\n", constants.ColorCyan, constants.LogPrefixAvaliator, constants.ColorReset, constants.ColorRed, err, constants.ColorReset)
		return
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		fmt.Fprintf(os.Stderr, "%s%s%s: %sMetrics API returned non-200 status code: %d%s\n", constants.ColorCyan, constants.LogPrefixAvaliator, constants.ColorReset, constants.ColorRed, resp.StatusCode, constants.ColorReset)
		return
	}

	body, err := ioutil.ReadAll(resp.Body)
	if err != nil {
		fmt.Fprintf(os.Stderr, "%s%s%s: %sError reading metrics response body: %v%s\n", constants.ColorCyan, constants.LogPrefixAvaliator, constants.ColorReset, constants.ColorRed, err, constants.ColorReset)
		return
	}

	err = ioutil.WriteFile(constants.MetricsFilePath, body, 0644)
	if err != nil {
		fmt.Fprintf(os.Stderr, "%s%s%s: %sError writing metrics file: %v%s\n", constants.ColorCyan, constants.LogPrefixAvaliator, constants.ColorReset, constants.ColorRed, err, constants.ColorReset)
		return
	}
	fmt.Printf("%s%s%s: %sMetrics data saved to %s%s\n",
		constants.ColorCyan, constants.LogPrefixAvaliator, constants.ColorReset, constants.ColorGreen, constants.MetricsFilePath, constants.ColorReset)

	cmdProcess := exec.Command(constants.PythonExecutable, constants.ProcessJSONScript, constants.MetricsFilePath, constants.ProcessedMetricsPath)
	cmdProcess.Stdout = os.Stdout
	cmdProcess.Stderr = os.Stderr
	if err := cmdProcess.Run(); err != nil {
		fmt.Fprintf(os.Stderr, "%s%s%s: %sError running process_json.py: %v%s\n", constants.ColorCyan, constants.LogPrefixAvaliator, constants.ColorReset, constants.ColorRed, err, constants.ColorReset)
		return
	}

	cmdAvaliate := exec.Command(constants.PythonExecutable, constants.AvaliatorScript, constants.ProcessedMetricsPath)
	cmdAvaliate.Stdout = os.Stdout
	cmdAvaliate.Stderr = os.Stderr
	if err := cmdAvaliate.Run(); err != nil {
		fmt.Fprintf(os.Stderr, "%s%s%s: %sError running avaliator.py: %v%s\n", constants.ColorCyan, constants.LogPrefixAvaliator, constants.ColorReset, constants.ColorRed, err, constants.ColorReset)
		return
	}
	fmt.Printf("%s%s%s: %sFinished generating visualizations.%s\n",
		constants.ColorCyan, constants.LogPrefixAvaliator, constants.ColorReset, constants.ColorGreen, constants.ColorReset)

	if err := os.Remove(constants.MetricsFilePath); err != nil {
		fmt.Fprintf(os.Stderr, "%s%s%s: %sError deleting %s: %v%s\n", constants.ColorCyan, constants.LogPrefixAvaliator, constants.ColorReset, constants.ColorRed, constants.MetricsFilePath, err, constants.ColorReset)
	}
	if err := os.Remove(constants.ProcessedMetricsPath); err != nil {
		fmt.Fprintf(os.Stderr, "%s%s%s: %sError deleting %s: %v%s\n", constants.ColorCyan, constants.LogPrefixAvaliator, constants.ColorReset, constants.ColorRed, constants.ProcessedMetricsPath, err, constants.ColorReset)
	}
}
