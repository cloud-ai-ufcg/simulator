package avaliator

import (
	"io/ioutil"
	"net/http"
	"os"
	"os/exec"
	"simulator/internal/constants"
	"simulator/internal/log"
)

func CallAvaliatorAndProcess() {
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

	err = ioutil.WriteFile(constants.MetricsFilePath, body, 0644)
	if err != nil {
		log.Errorf("Error writing metrics file: %v", err)
		return
	}
	cmdProcess := exec.Command(constants.PythonExecutable, constants.ProcessJSONScript, constants.MetricsFilePath, constants.ProcessedMetricsPath)
	cmdProcess.Stdout = os.Stdout
	cmdProcess.Stderr = os.Stderr
	if err := cmdProcess.Run(); err != nil {
		log.Errorf("Error running process_json.py: %v", err)
		return
	}

	cmdAvaliate := exec.Command(constants.PythonExecutable, constants.AvaliatorScript, constants.ProcessedMetricsPath)
	cmdAvaliate.Stdout = os.Stdout
	cmdAvaliate.Stderr = os.Stderr
	if err := cmdAvaliate.Run(); err != nil {
		log.Errorf("Error running avaliator.py: %v", err)
		return
	}

	cmdPlot := exec.Command(constants.PythonExecutable, constants.PlotResourcesScript)
	cmdPlot.Stdout = os.Stdout
	cmdPlot.Stderr = os.Stderr
	if err := cmdPlot.Run(); err != nil {
		log.Errorf("Error running plot_resources.py: %v", err)
		return
	}

	log.Infof("Finished generating visualizations.")

	if err := os.Remove(constants.MetricsFilePath); err != nil {
		log.Errorf("Error deleting %s: %v", constants.MetricsFilePath, err)
	}
	if err := os.Remove(constants.ProcessedMetricsPath); err != nil {
		log.Errorf("Error deleting %s: %v", constants.ProcessedMetricsPath, err)
	}
}
