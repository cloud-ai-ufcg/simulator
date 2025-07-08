package constants

// ANSI Color Codes
const (
	ColorReset  = "\033[0m"
	ColorRed    = "\033[31m"
	ColorGreen  = "\033[32m"
	ColorYellow = "\033[33m"
	ColorBlue   = "\033[34m"
	ColorPurple = "\033[35m"
	ColorCyan   = "\033[36m"
)

// Log Prefixes
const (
	LogPrefixSimulator = "Simulator"
	LogPrefixBroker    = "Broker"
	LogPrefixMonitor   = "Monitor"
	LogPrefixAIEngine  = "AI-Engine"
	LogPrefixActuator  = "Actuator"
	LogPrefixAvaliator = "Avaliator"
)

// Paths and names
const (
	MonitorDirName    = "monitor"
	MonitorOutputBase = "../data/output/monitor_outputs.json" // This relative path may need adjustment depending on where it is used

	AIEngineParentDirName = "ai-engine"
	AIEngineWorkSubDir    = "engine"
	AIEngineOutputCSVPath = "data/output/recommendations.csv" // This relative path may need adjustment

	ActuatorDirName      = "actuator"
	ActuatorInputCSVName = "recommendations.csv" // This relative path may need adjustment
)
