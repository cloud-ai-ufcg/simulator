package main

import (
	"fmt"
	"io/ioutil"
	"net/http"
	"os"
	"os/exec"
	"simulator/api"
	"simulator/constants"
)

func callAvaliatorAndProcess() {
	metricsURL := "http://localhost:8082/metrics"
	fmt.Printf("%s%s%s: %sCalling metrics endpoint at %s...%s\n",
		constants.ColorCyan, constants.LogPrefixSimulator, constants.ColorReset, constants.ColorBlue, metricsURL, constants.ColorReset)

	resp, err := http.Get(metricsURL)
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

	metricsFilePath := "avaliator/data/metrics.json"
	err = ioutil.WriteFile(metricsFilePath, body, 0644)
	if err != nil {
		fmt.Fprintf(os.Stderr, "%s%s%s: %sError writing metrics file: %v%s\n", constants.ColorCyan, constants.LogPrefixAvaliator, constants.ColorReset, constants.ColorRed, err, constants.ColorReset)
		return
	}
	fmt.Printf("%s%s%s: %sMetrics data saved to %s%s\n",
		constants.ColorCyan, constants.LogPrefixAvaliator, constants.ColorReset, constants.ColorGreen, metricsFilePath, constants.ColorReset)

	processedFilePath := "avaliator/data/processed_metrics.json"
	cmdProcess := exec.Command("python3", "avaliator/process_json.py", metricsFilePath, processedFilePath)
	cmdProcess.Stdout = os.Stdout
	cmdProcess.Stderr = os.Stderr
	if err := cmdProcess.Run(); err != nil {
		fmt.Fprintf(os.Stderr, "%s%s%s: %sError running process_json.py: %v%s\n", constants.ColorCyan, constants.LogPrefixAvaliator, constants.ColorReset, constants.ColorRed, err, constants.ColorReset)
		return
	}
	fmt.Printf("%s%s%s: %sFinished processing metrics data.%s\n",
		constants.ColorCyan, constants.LogPrefixAvaliator, constants.ColorReset, constants.ColorGreen, constants.ColorReset)

	cmdAvaliate := exec.Command("python3", "avaliator/avaliator.py", processedFilePath)
	cmdAvaliate.Stdout = os.Stdout
	cmdAvaliate.Stderr = os.Stderr
	if err := cmdAvaliate.Run(); err != nil {
		fmt.Fprintf(os.Stderr, "%s%s%s: %sError running avaliator.py: %v%s\n", constants.ColorCyan, constants.LogPrefixAvaliator, constants.ColorReset, constants.ColorRed, err, constants.ColorReset)
		return
	}
	fmt.Printf("%s%s%s: %sFinished generating visualizations.%s\n",
		constants.ColorCyan, constants.LogPrefixAvaliator, constants.ColorReset, constants.ColorGreen, constants.ColorReset)
}

func main() {
	// Print webSC banner
	fmt.Println(`                                                                                                                                                                                                   
                                                                           ███                                    
                                                                      █████ ██                                    
                                                                   ████    ██                                     
                                                                ███            ████████                           
                                                             ███         ██████     ██                            
                         ████████                         ███       █████          ██░                            
                                 █                     ███     █████              ██                              
                      ███████  ██ ██                ████   ████▒                ███                               
                                 █████████ █████  █████████                  ███▒                                 
                                 ███ ░█  ███      ████▓                   ████                                    
                                ██ ████  ██    ███            ▒███████████                                        
                               ██ █████ ███     ███████████████   ████                                            
                               ██  ▓  ███ ██               █   ███    ████                                        
 ████████████████████████████  ██ █████   █████           ██████         ███████████████████████████████████████  
                               ████    ████   ███      ███    ██       ██  ██                                     
                                    ████        █████████    █ ██    ██░    ██                                    
                                 ████          ██    ██ ░██████▒█████       ██                                    
                              ███            ██       ██     ██  ██     ████ ██                                   
                                           ██          ██     ██  ░██████    ██                                   
                                                         ██    ██    ██     ███                                   
                        █   █   █   ██   ▒███▒ █████      ██    ██     █████ ██                                   
                        ██ █ █ ██  █ █   ██    ██  ██            ███     ██ ██                                    
                         █ █ █ █  █████     ██ █████               ███    ████                                    
                          █   █░ ██    █ ████▒ ██                    ███    █                                     
                                                                        █░      
																		                                  `)

	fmt.Printf("%s%s%s: %sStarting sequential operation cycle...%s\n",
		constants.ColorCyan, constants.LogPrefixSimulator, constants.ColorReset, constants.ColorBlue, constants.ColorReset)
	fmt.Println("")

	// 1. Broker via API
	apiURL := "http://localhost:8080/broker/"
	inputFilePath := "data/input_json.json" // Relative to the project root

	// 2. AI Engine via API
	aiEngineRoute := os.Getenv("AI_ENGINE_ROUTE")
	if aiEngineRoute == "" {
		aiEngineRoute = "/start"
	}
	aiEngineAPIURL := "http://0.0.0.0:8083" + aiEngineRoute
	go func() {
		if err := api.CallAIEngineAPI(aiEngineAPIURL); err != nil {
			fmt.Fprintf(os.Stderr, "%s%s%s: %sError calling AI-Engine API: %v%s\n", constants.ColorCyan, constants.LogPrefixAIEngine, constants.ColorReset, constants.ColorRed, err, constants.ColorReset)
		}
	}()

	if err := api.CallBrokerAPI(inputFilePath, apiURL); err != nil {
		fmt.Fprintf(os.Stderr, "%s%s%s: %sError calling Broker API: %v%s\n", constants.ColorCyan, constants.LogPrefixBroker, constants.ColorReset, constants.ColorRed, err, constants.ColorReset)
		os.Exit(1)
	}

	callAvaliatorAndProcess()

	fmt.Printf("\n%s%s%s: %sAll operations completed successfully.%s\n",
		constants.ColorCyan, constants.LogPrefixSimulator, constants.ColorReset, constants.ColorGreen, constants.ColorReset)
	fmt.Printf("%s%s%s: %sSequential execution cycle finished.%s\n",
		constants.ColorCyan, constants.LogPrefixSimulator, constants.ColorReset, constants.ColorGreen, constants.ColorReset)
}
