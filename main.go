package main

import (
	"fmt"
	"os"
	"simulator/api"
	"simulator/constants"
)

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
	if err := api.CallBrokerAPI(inputFilePath, apiURL); err != nil {
		fmt.Fprintf(os.Stderr, "%s%s%s: %sError calling Broker API: %v%s\n", constants.ColorCyan, constants.LogPrefixBroker, constants.ColorReset, constants.ColorRed, err, constants.ColorReset)
		os.Exit(1)
	}

	fmt.Println("")

	// 2. AI Engine via API
	aiEngineRoute := os.Getenv("AI_ENGINE_ROUTE")
	if aiEngineRoute == "" {
		aiEngineRoute = "/start"
	}
	aiEngineAPIURL := "http://0.0.0.0:8083" + aiEngineRoute
	if err := api.CallAIEngineAPI(aiEngineAPIURL); err != nil {
		fmt.Fprintf(os.Stderr, "%s%s%s: %sError calling AI-Engine API: %v%s\n", constants.ColorCyan, constants.LogPrefixAIEngine, constants.ColorReset, constants.ColorRed, err, constants.ColorReset)
		os.Exit(1)
	}

	fmt.Printf("\n%s%s%s: %sAll operations completed successfully.%s\n",
		constants.ColorCyan, constants.LogPrefixSimulator, constants.ColorReset, constants.ColorGreen, constants.ColorReset)
	fmt.Printf("%s%s%s: %sSequential execution cycle finished.%s\n",
		constants.ColorCyan, constants.LogPrefixSimulator, constants.ColorReset, constants.ColorGreen, constants.ColorReset)
}
