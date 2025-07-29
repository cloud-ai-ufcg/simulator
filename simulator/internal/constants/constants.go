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
	APIURLBroker       = "http://localhost:8080/broker/"
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
	LogPrefixAvaliator = "Avaliator"
)

// Avaliator constants
const (
	MetricsURL           = "http://localhost:8082/metrics"
	MetricsFilePath      = "../../avaliator/data/metrics.json"
	ProcessedMetricsPath = "../../avaliator/data/processed_metrics.json"
	PythonExecutable     = "../../venv/bin/python"
	ProcessJSONScript    = "../../avaliator/process_json.py"
	AvaliatorScript      = "../../avaliator/avaliator.py"
)

// Absolute path to the logs directory
const LogsDir = "../data/output/logs"

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
                                                                                        `
