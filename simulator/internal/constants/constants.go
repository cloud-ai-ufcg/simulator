package constants

// Container names
const (
	ContainerActuator = "actuator"
	ContainerBroker   = "broker"
	ContainerMonitor  = "monitor"
	ContainerAIEngine = "ai-engine"
)

// API routes
const (
	APIURLBroker       = "http://localhost:8081/broker/"
	APIURLAIEngine     = "http://0.0.0.0:8083/start"
	APIURLAIEngineStop = "http://0.0.0.0:8083/stop"
)

// ANSI color codes
const (
	ColorReset  = "\033[0m"
	ColorRed    = "\033[31m"
	ColorGreen  = "\033[32m"
	ColorYellow = "\033[33m"
	ColorBlue   = "\033[34m"
	ColorPurple = "\033[35m"
	ColorCyan   = "\033[36m"
)

// Log prefixes
const (
	LogPrefixSimulator = "Simulator"
	LogPrefixBroker    = "Broker"
	LogPrefixMonitor   = "Monitor"
	LogPrefixAIEngine  = "AI-Engine"
	LogPrefixActuator  = "Actuator"
	LogPrefixAnalyzer  = "Analyzer"
)

// Analyzer constants
const (
	// API and file paths
	MetricsURL      = "http://localhost:8082/metrics"
	MetricsFilePath = "../../analyzer/dataplots/metrics.json"

	// Python configuration
	PythonExecutable = "../../venv/bin/python3"

	// Output directories
	OutputDir    = "../../simulator/data/output/plots"
	LogsDir      = "../../simulator/data/output/logs"
	DataplotsDir = "../../analyzer/dataplots"
)

// Simulator ASCII logo
const SimulatorLogo = `                                                                                                                                                                                                   
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
 ████████████████████████████  ██ █████   █████           ██████         ██  ███████████████████████████████████  
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
                                                                                        `
