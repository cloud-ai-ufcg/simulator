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
	LogPrefixSimulator = " Simulador"
	LogPrefixBroker    = " Broker"
	LogPrefixMonitor   = " Monitor"
	LogPrefixAIEngine  = " AI-Engine"
	LogPrefixActuator  = " Actuator"
)

// Paths and names
const (
	MonitorDirName    = "monitor"
	MonitorOutputBase = "../data/output/monitor_outputs.json" // Este caminho relativo pode precisar de ajuste dependendo de onde é usado

	AIEngineParentDirName = "ai-engine"
	AIEngineWorkSubDir    = "engine"
	AIEngineOutputCSVPath = "data/output/recommendations.csv" // Este caminho relativo pode precisar de ajuste

	ActuatorDirName      = "actuator"
	ActuatorInputCSVName = "recommendations.csv" // Este caminho relativo pode precisar de ajuste
)
