package main

import (
	// "encoding/json" // Verifique se ainda é necessário
	"fmt"
	// "log" // Será substituído por fmt
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"

	"github.com/cloud-ai-ufcg/broker/broker"
)

// ANSI Color Codes
const (
	colorReset  = "\033[0m"
	colorRed    = "\033[31m"
	colorGreen  = "\033[32m"
	colorYellow = "\033[33m"
	colorBlue   = "\033[34m"
	colorPurple = "\033[35m"
	colorCyan   = "\033[36m"
)

// Emojis
const (
	emojiRocket    = "🚀"
	emojiBroker    = "💼"
	emojiMonitor   = "📡"
	emojiAIEngine  = "🧠"
	emojiActuator  = "🛠️"
	emojiSuccess   = "✅"
	emojiError     = "❌"
	emojiFire      = "🔥"
	emojiWarning   = "⚠️"
	emojiInfo      = "ℹ️"
	emojiPlay      = "▶️"
	emojiStop      = "⏹️"
	emojiTool      = "🔧"
	emojiClean     = "🧹"
	emojiOutput    = "💬"
	emojiFile      = "📄"
	emojiDirectory = "📁"
	emojiConfig    = "⚙️"
	emojiKill      = "🔪"
)

const (
	logPrefixSimulator = emojiRocket + " Simulador"
	logPrefixBroker    = emojiBroker + " Broker"
	logPrefixMonitor   = emojiMonitor + " Monitor"
	logPrefixAIEngine  = emojiAIEngine + " AI-Engine"
	logPrefixActuator  = emojiActuator + " Actuator"
)

// Paths and names (existing constants)
const (
	monitorDirName    = "monitor"
	monitorOutputBase = "monitor_outputs.json"

	aiEngineParentDirName  = "ai-engine"
	aiEngineWorkSubDir     = "engine"
	aiEngineTempConfigYAML = "temp_ai_runtime_config.yaml"
	aiEngineOutputCSVPath  = "ai-engine/actuator/recommendations.csv"

	actuatorDirName      = "actuator"
	actuatorInputCSVName = "recommendations.csv"

	brokerInputDataCSVPath    = "data/recorte_5min.csv"
	brokerInputConfigYAMLPath = "data/config.yaml"
)

func forceKillMonitorProcesses() {
	fmt.Printf("%s%s%s: %s Forçando encerramento de processos antigos do monitor...%s\n", colorCyan, logPrefixMonitor, colorReset, emojiClean, colorReset)
	processesToKill := []struct {
		name    string
		pattern string
	}{
		{"port-foward.sh", "port-foward.sh"},
		{"kubectl port-forward", "kubectl.*port-forward"},
		{"./monitor executable", "./monitor"},
	}

	for _, proc := range processesToKill {
		cmd := exec.Command("pkill", "-KILL", "-f", proc.pattern)
		output, err := cmd.CombinedOutput()
		if err != nil {
			if !(strings.Contains(string(output), "no process found") || strings.Contains(err.Error(), "exit status 1")) {
				fmt.Printf("%s%s%s: %s Erro ao tentar forçar o encerramento de '%s%s%s': %v. Output: %s%s\n",
					colorCyan, logPrefixMonitor, colorReset, emojiError, colorPurple, proc.pattern, colorRed, err, string(output), colorReset)
			}
		} else {
			fmt.Printf("%s%s%s: %s Sinal KILL enviado com sucesso para processos correspondentes a '%s%s%s'. Output: %s%s\n",
				colorCyan, logPrefixMonitor, colorReset, emojiKill, colorPurple, proc.name, colorGreen, string(output), colorReset)
		}
	}
	time.Sleep(100 * time.Millisecond)
}

func runExternalMonitorAndFetchOutput(duration time.Duration) (string, error) {
	forceKillMonitorProcesses()

	fmt.Printf("%s%s%s: %s Iniciando...%s\n", colorCyan, logPrefixMonitor, colorReset, emojiPlay, colorReset)

	originalWd, err := os.Getwd()
	if err != nil {
		fmt.Fprintf(os.Stderr, "%s%s%s: %s Falha ao obter diretório de trabalho atual: %v%s\n", colorCyan, logPrefixMonitor, colorReset, emojiError, err, colorReset)
		return "", fmt.Errorf("falha ao obter diretório de trabalho atual: %w", err)
	}

	if err := os.Chdir(monitorDirName); err != nil {
		fmt.Fprintf(os.Stderr, "%s%s%s: %s Falha ao mudar para o diretório %s%s%s: %v%s\n", colorCyan, logPrefixMonitor, colorReset, emojiError, colorPurple, monitorDirName, colorRed, err, colorReset)
		return "", fmt.Errorf("falha ao mudar para o diretório %s: %w", monitorDirName, err)
	}
	defer func() {
		fmt.Printf("%s%s%s: %s Voltando para o diretório original %s%s%s...%s\n",
			colorCyan, logPrefixMonitor, colorReset, emojiDirectory, colorPurple, originalWd, colorBlue, colorReset)
		if err := os.Chdir(originalWd); err != nil {
			fmt.Fprintf(os.Stderr, "%s%s%s: %s CRÍTICO - Falha ao voltar para o diretório original %s%s%s: %v. Encerrando.%s\n",
				colorCyan, logPrefixMonitor, colorReset, emojiFire, colorPurple, originalWd, colorRed, err, colorReset)
			os.Exit(1)
		}
	}()

	fmt.Printf("%s%s%s: %s Executando 'make all' em %s%s%s por %s%v%s...%s\n",
		colorCyan, logPrefixMonitor, colorReset, emojiTool, colorPurple, monitorDirName, colorBlue, colorPurple, duration, colorBlue, colorReset)
	cmd := exec.Command("make", "all")

	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr

	if err := cmd.Start(); err != nil {
		fmt.Fprintf(os.Stderr, "%s%s%s: %s Falha ao iniciar 'make all': %v%s\n", colorCyan, logPrefixMonitor, colorReset, emojiError, err, colorReset)
		return "", fmt.Errorf("falha ao iniciar 'make all': %w", err)
	}

	fmt.Printf("%s%s%s: %s Processo iniciado (PID %s%d%s), aguardando %s%v%s...%s\n",
		colorCyan, logPrefixMonitor, colorReset, emojiInfo, colorPurple, cmd.Process.Pid, colorBlue, colorPurple, duration, colorBlue, colorReset)
	time.Sleep(duration)

	fmt.Printf("%s%s%s: %s Duração esgotada. Enviando sinal de interrupção para 'make all'...%s\n",
		colorCyan, logPrefixMonitor, colorReset, emojiStop, colorReset)
	if err := cmd.Process.Signal(os.Interrupt); err != nil {
		fmt.Printf("%s%s%s: %s %s Falha ao enviar sinal de interrupção: %v. Tentando aguardar processo.%s\n",
			colorCyan, logPrefixMonitor, colorReset, emojiWarning, emojiError, err, colorReset)
	}

	fmt.Printf("%s%s%s: %s Aguardando 'make all' completar limpeza e sair...%s\n",
		colorCyan, logPrefixMonitor, colorReset, emojiInfo, colorReset)

	waitChan := make(chan error, 1)
	go func() {
		waitChan <- cmd.Wait()
	}()

	select {
	case err := <-waitChan:
		if err != nil {
			if exitErr, ok := err.(*exec.ExitError); ok {
				fmt.Printf("%s%s%s: %s 'make all' saiu com erro após interrupção: %v. Stderr: %s%s%s\n",
					colorCyan, logPrefixMonitor, colorReset, emojiError, exitErr, colorRed, string(exitErr.Stderr), colorReset)
			} else {
				fmt.Printf("%s%s%s: %s 'make all' falhou ao completar após interrupção: %v%s\n",
					colorCyan, logPrefixMonitor, colorReset, emojiError, err, colorReset)
			}
		} else {
			fmt.Printf("%s%s%s: %s 'make all' completado com sucesso após interrupção.%s\n",
				colorCyan, logPrefixMonitor, colorReset, emojiSuccess, colorReset)
		}
	case <-time.After(5 * time.Second):
		fmt.Printf("%s%s%s: %s %s 'make all' não saiu prontamente após interrupção. Enviando sinal KILL...%s\n",
			colorCyan, logPrefixMonitor, colorReset, emojiWarning, emojiKill, colorReset)
		if killErr := cmd.Process.Kill(); killErr != nil {
			fmt.Printf("%s%s%s: %s %s Falha ao enviar sinal KILL: %v%s\n",
				colorCyan, logPrefixMonitor, colorReset, emojiWarning, emojiError, killErr, colorReset)
			<-waitChan
			fmt.Fprintf(os.Stderr, "%s%s%s: %s Falha ao matar processo 'make all' após timeout: %v%s\n", colorCyan, logPrefixMonitor, colorReset, emojiFire, killErr, colorReset)
			return "", fmt.Errorf("falha ao matar processo 'make all' após timeout: %w", killErr)
		}
		finalWaitErr := <-waitChan
		fmt.Printf("%s%s%s: %s Processo 'make all' morto. Resultado do Wait: %v%s\n",
			colorCyan, logPrefixMonitor, colorReset, emojiKill, finalWaitErr, colorReset)
	}

	forceKillMonitorProcesses()

	originalMonitorOutputPath := monitorOutputBase
	fullOriginalMonitorPath := filepath.Join(originalWd, monitorDirName, monitorOutputBase)

	fmt.Printf("%s%s%s: %s Verificando arquivo de saída do monitor em %s%s%s (dentro de %s%s%s)...%s\n",
		colorCyan, logPrefixMonitor, colorReset, emojiFile, colorPurple, originalMonitorOutputPath, colorBlue, colorPurple, monitorDirName, colorBlue, colorReset)
	if _, err := os.Stat(originalMonitorOutputPath); os.IsNotExist(err) {
		fmt.Fprintf(os.Stderr, "%s%s%s: %s Arquivo de saída do monitor %s%s%s não encontrado em %s%s%s após execução: %v%s\n", colorCyan, logPrefixMonitor, colorReset, emojiError, colorPurple, originalMonitorOutputPath, colorRed, colorPurple, monitorDirName, colorRed, err, colorReset)
		return "", fmt.Errorf("arquivo de saída do monitor %s não encontrado em %s após execução: %w", originalMonitorOutputPath, monitorDirName, err)
	}

	returnedPath := filepath.Join(monitorDirName, monitorOutputBase)
	fmt.Printf("%s%s%s: %s Monitor finalizado. Saída disponível em %s%s%s.%s\n",
		colorCyan, logPrefixMonitor, colorReset, emojiSuccess, colorPurple, fullOriginalMonitorPath, colorGreen, colorReset)
	return returnedPath, nil
}

func runAIEngine(monitorStaticFile string) (string, error) {
	fmt.Printf("%s%s%s: %s Iniciando. Input estático do monitor: %s%s%s\n",
		colorCyan, logPrefixAIEngine, colorReset, emojiPlay, colorPurple, monitorStaticFile, colorReset)

	aiEngineTopDir := aiEngineParentDirName
	aiEngineWorkDir := filepath.Join(aiEngineTopDir, aiEngineWorkSubDir)

	tempRuntimeConfigFile := aiEngineTempConfigYAML
	recommendationsFileRel := aiEngineOutputCSVPath

	absMonitorStaticFile, err := filepath.Abs(monitorStaticFile)
	if err != nil {
		fmt.Fprintf(os.Stderr, "%s%s%s: %s Falha ao obter caminho absoluto para o arquivo de monitor %s%s%s: %v%s\n", colorCyan, logPrefixAIEngine, colorReset, emojiError, colorPurple, monitorStaticFile, colorRed, err, colorReset)
		return "", fmt.Errorf("falha ao obter caminho absoluto para o arquivo de monitor %s: %w", monitorStaticFile, err)
	}

	absAiEngineWorkDir, err := filepath.Abs(aiEngineWorkDir)
	if err != nil {
		fmt.Fprintf(os.Stderr, "%s%s%s: %s Falha ao obter caminho absoluto para o diretório de trabalho do AI Engine %s%s%s: %v%s\n", colorCyan, logPrefixAIEngine, colorReset, emojiError, colorPurple, aiEngineWorkDir, colorRed, err, colorReset)
		return "", fmt.Errorf("falha ao obter caminho absoluto para o diretório de trabalho do AI Engine %s: %w", aiEngineWorkDir, err)
	}

	relativePathToMonitorFileForAI, err := filepath.Rel(absAiEngineWorkDir, absMonitorStaticFile)
	if err != nil {
		fmt.Fprintf(os.Stderr, "%s%s%s: %s Falha ao calcular o caminho relativo de %s%s%s para %s%s%s: %v%s\n", colorCyan, logPrefixAIEngine, colorReset, emojiError, colorPurple, absAiEngineWorkDir, colorRed, colorPurple, absMonitorStaticFile, colorRed, err, colorReset)
		return "", fmt.Errorf("falha ao calcular o caminho relativo de %s para %s: %w", absAiEngineWorkDir, absMonitorStaticFile, err)
	}
	fmt.Printf("%s%s%s: %s AI Engine usará o arquivo de input: %s%s%s (relativo a %s%s%s)%s\n",
		colorCyan, logPrefixAIEngine, colorReset, emojiInfo, colorPurple, relativePathToMonitorFileForAI, colorBlue, colorPurple, aiEngineWorkDir, colorBlue, colorReset)

	yamlContent := fmt.Sprintf("data:\n  input_json: \"%s\"\n", relativePathToMonitorFileForAI)
	absTempRuntimeConfigFile := filepath.Join(aiEngineWorkDir, tempRuntimeConfigFile)
	fmt.Printf("%s%s%s: %s Escrevendo YAML de configuração temporário para: %s%s%s\n",
		colorCyan, logPrefixAIEngine, colorReset, emojiConfig, colorPurple, absTempRuntimeConfigFile, colorReset)
	if err := os.WriteFile(absTempRuntimeConfigFile, []byte(yamlContent), 0644); err != nil {
		fmt.Fprintf(os.Stderr, "%s%s%s: %s Falha ao escrever YAML de configuração temporário %s%s%s: %v%s\n", colorCyan, logPrefixAIEngine, colorReset, emojiError, colorPurple, absTempRuntimeConfigFile, colorRed, err, colorReset)
		return "", fmt.Errorf("falha ao escrever YAML de configuração temporário %s: %w", absTempRuntimeConfigFile, err)
	}
	defer func() {
		fmt.Printf("%s%s%s: %s Removendo arquivo YAML de configuração temporário: %s%s%s\n",
			colorCyan, logPrefixAIEngine, colorReset, emojiClean, colorPurple, absTempRuntimeConfigFile, colorReset)
		os.Remove(absTempRuntimeConfigFile)
	}()

	makeTarget := "run-with-config"
	makeConfigFileVar := "CONFIG_FILE=" + tempRuntimeConfigFile

	fmt.Printf("%s%s%s: %s Executando via Makefile: %smake %s %s%s (CWD: %s%s%s)%s\n",
		colorCyan, logPrefixAIEngine, colorReset, emojiTool, colorPurple, makeTarget, makeConfigFileVar, colorBlue, colorPurple, aiEngineTopDir, colorBlue, colorReset)
	cmd := exec.Command("make", makeTarget, makeConfigFileVar)
	cmd.Dir = aiEngineTopDir

	cmdOutput, err := cmd.CombinedOutput()
	if err != nil {
		fmt.Printf("%s%s%s: %s --- %s AI-Engine Output Start (Error) %s --- %s\n", colorCyan, logPrefixAIEngine, colorReset, emojiOutput, colorYellow, emojiOutput, colorReset)
		fmt.Print(string(cmdOutput)) // Raw output, no extra newline
		fmt.Printf("%s%s%s: %s --- %s AI-Engine Output End (Error) %s --- %s\n", colorCyan, logPrefixAIEngine, colorReset, emojiOutput, colorYellow, emojiOutput, colorReset)
		fmt.Fprintf(os.Stderr, "%s%s%s: %s Falha ao executar Makefile target '%s%s%s' com config (%s%s%s): %v%s\n", colorCyan, logPrefixAIEngine, colorReset, emojiError, colorPurple, makeTarget, colorRed, colorPurple, tempRuntimeConfigFile, colorRed, err, colorReset)
		return "", fmt.Errorf("falha ao executar Makefile target '%s' com config (%s): %w", makeTarget, tempRuntimeConfigFile, err)
	}
	fmt.Printf("%s%s%s: %s Makefile target executado.%s\n", colorCyan, logPrefixAIEngine, colorReset, emojiSuccess, colorReset)
	fmt.Printf("%s%s%s: %s --- %s AI-Engine Output Start %s --- %s\n", colorCyan, logPrefixAIEngine, colorReset, emojiOutput, colorGreen, emojiOutput, colorReset)
	fmt.Print(string(cmdOutput)) // Raw output, no extra newline
	fmt.Printf("%s%s%s: %s --- %s AI-Engine Output End %s --- %s\n", colorCyan, logPrefixAIEngine, colorReset, emojiOutput, colorGreen, emojiOutput, colorReset)

	absRecommendationsFile, err := filepath.Abs(recommendationsFileRel)
	if err != nil {
		fmt.Fprintf(os.Stderr, "%s%s%s: %s Erro ao obter caminho absoluto para %s%s%s: %v%s\n", colorCyan, logPrefixAIEngine, colorReset, emojiError, colorPurple, recommendationsFileRel, colorRed, err, colorReset)
		return "", fmt.Errorf("erro ao obter caminho absoluto para %s: %w", recommendationsFileRel, err)
	}

	if _, err := os.Stat(absRecommendationsFile); os.IsNotExist(err) {
		fmt.Fprintf(os.Stderr, "%s%s%s: %s Arquivo de recomendações esperado (%s%s%s) não foi encontrado após execução%s\n", colorCyan, logPrefixAIEngine, colorReset, emojiError, colorPurple, absRecommendationsFile, colorRed, colorReset)
		return "", fmt.Errorf("arquivo de recomendações esperado (%s) não foi encontrado após execução", absRecommendationsFile)
	}

	fmt.Printf("%s%s%s: %s Finalizado. Recomendações esperadas em %s%s%s.%s\n",
		colorCyan, logPrefixAIEngine, colorReset, emojiSuccess, colorPurple, absRecommendationsFile, colorGreen, colorReset)
	return absRecommendationsFile, nil
}

func runActuator(recommendationsCsvFile string) error {
	fmt.Printf("%s%s%s: %s Iniciando. Input original: %s%s%s\n",
		colorCyan, logPrefixActuator, colorReset, emojiPlay, colorPurple, recommendationsCsvFile, colorReset)

	currentActuatorDir := actuatorDirName
	destCsvInActuatorDir := filepath.Join(currentActuatorDir, actuatorInputCSVName)

	fmt.Printf("%s%s%s: %s Copiando %s%s%s para %s%s%s%s\n",
		colorCyan, logPrefixActuator, colorReset, emojiFile, colorPurple, recommendationsCsvFile, colorBlue, colorPurple, destCsvInActuatorDir, colorBlue, colorReset)
	sourceData, err := os.ReadFile(recommendationsCsvFile)
	if err != nil {
		fmt.Fprintf(os.Stderr, "%s%s%s: %s falha ao ler arquivo de recomendações original %s%s%s: %v%s\n", colorCyan, logPrefixActuator, colorReset, emojiError, colorPurple, recommendationsCsvFile, colorRed, err, colorReset)
		return fmt.Errorf("falha ao ler arquivo de recomendações original %s: %w", recommendationsCsvFile, err)
	}
	if err := os.WriteFile(destCsvInActuatorDir, sourceData, 0644); err != nil {
		fmt.Fprintf(os.Stderr, "%s%s%s: %s falha ao escrever recomendações para %s%s%s: %v%s\n", colorCyan, logPrefixActuator, colorReset, emojiError, colorPurple, destCsvInActuatorDir, colorRed, err, colorReset)
		return fmt.Errorf("falha ao escrever recomendações para %s: %w", destCsvInActuatorDir, err)
	}
	defer func() {
		fmt.Printf("%s%s%s: %s Removendo arquivo de recomendações copiado: %s%s%s\n",
			colorCyan, logPrefixActuator, colorReset, emojiClean, colorPurple, destCsvInActuatorDir, colorReset)
		os.Remove(destCsvInActuatorDir)
	}()

	fmt.Printf("%s%s%s: %s Executando programa Go: %sgo run main.go%s no diretório %s%s%s%s\n",
		colorCyan, logPrefixActuator, colorReset, emojiTool, colorPurple, colorBlue, colorPurple, currentActuatorDir, colorBlue, colorReset)

	cmd := exec.Command("go", "run", "main.go")
	cmd.Dir = currentActuatorDir

	cmdOutput, err := cmd.CombinedOutput()
	if err != nil {
		fmt.Printf("%s%s%s: %s Falha ao executar programa Go (go run main.go em %s%s%s): %v%s\n",
			colorCyan, logPrefixActuator, colorReset, emojiError, colorPurple, currentActuatorDir, colorRed, err, colorReset)
		fmt.Printf("%s%s%s: %s --- %s Actuator Output Start (Error) %s --- %s\n", colorCyan, logPrefixActuator, colorReset, emojiOutput, colorYellow, emojiOutput, colorReset)
		fmt.Print(string(cmdOutput)) // Raw output, no extra newline
		fmt.Printf("%s%s%s: %s --- %s Actuator Output End (Error) %s --- %s\n", colorCyan, logPrefixActuator, colorReset, emojiOutput, colorYellow, emojiOutput, colorReset)
		fmt.Fprintf(os.Stderr, "%s%s%s: %s falha ao executar programa Go: %v%s\n", colorCyan, logPrefixActuator, colorReset, emojiError, err, colorReset)
		return fmt.Errorf("falha ao executar programa Go: %w", err)
	}

	fmt.Printf("%s%s%s: %s Programa Go executado com sucesso.%s\n", colorCyan, logPrefixActuator, colorReset, emojiSuccess, colorReset)
	fmt.Printf("%s%s%s: %s --- %s Actuator Output Start %s --- %s\n", colorCyan, logPrefixActuator, colorReset, emojiOutput, colorGreen, emojiOutput, colorReset)
	fmt.Print(string(cmdOutput)) // Raw output, no extra newline
	fmt.Printf("%s%s%s: %s --- %s Actuator Output End %s --- %s\n", colorCyan, logPrefixActuator, colorReset, emojiOutput, colorGreen, emojiOutput, colorReset)
	fmt.Printf("%s%s%s: %s Finalizou a aplicação das recomendações.%s\n", colorCyan, logPrefixActuator, colorReset, emojiSuccess, colorReset)
	return nil
}

func main() {
	fmt.Println("")
	fmt.Printf("%s%s%s: Iniciando o ciclo de operações...%s\n", colorCyan, logPrefixSimulator, colorReset, colorReset)

	csvPath := brokerInputDataCSVPath
	yamlPath := brokerInputConfigYAMLPath

	configYaml, err := os.Open(yamlPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "%s%s%s: %s Falha ao abrir configuração YAML %s%s%s: %v%s\n",
			colorRed, logPrefixSimulator, colorReset, emojiFire, colorPurple, yamlPath, colorRed, err, colorReset)
		os.Exit(1)
	}

	csvData, err := os.Open(csvPath)
	if err != nil {
		fmt.Println("")
		fmt.Fprintf(os.Stderr, "%s%s%s: %s Falha ao abrir dados CSV %s%s%s: %v%s\n",
			colorRed, logPrefixSimulator, colorReset, emojiFire, colorPurple, csvPath, colorRed, err, colorReset)
		os.Exit(1)
	}

	fmt.Println("")
	fmt.Printf("%s%s%s: --- %s%s%s Iniciando --- %s\n", colorCyan, logPrefixSimulator, colorReset, colorCyan, logPrefixBroker, colorGreen, colorReset)
	broker.Run(csvData, configYaml)
	csvData.Close()
	configYaml.Close()
	fmt.Printf("%s%s%s: --- %s%s%s finalizado --- %s\n", colorCyan, logPrefixSimulator, colorReset, colorCyan, logPrefixBroker, colorGreen, colorReset)

	fmt.Println("")
	fmt.Printf("%s%s%s: --- %s%s%s Iniciando --- %s\n", colorCyan, logPrefixSimulator, colorReset, colorCyan, logPrefixMonitor, colorGreen, colorReset)
	monitorOutputFile, err := runExternalMonitorAndFetchOutput(10 * time.Second)
	if err != nil {
		fmt.Fprintf(os.Stderr, "%s%s%s: %s Falha: %v. Encerrando simulador.%s\n",
			colorRed, logPrefixMonitor, colorReset, emojiFire, err, colorReset)
		os.Exit(1)
	}
	fmt.Printf("%s%s%s: --- %s%s%s Output em: %s%s%s --- %s\n",
		colorCyan, logPrefixSimulator, colorReset, colorCyan, logPrefixMonitor, colorGreen, colorPurple, monitorOutputFile, colorGreen, colorReset)

	fmt.Println("")
	fmt.Printf("%s%s%s: --- %s%s%s Iniciando --- %s\n", colorCyan, logPrefixSimulator, colorReset, colorCyan, logPrefixAIEngine, colorGreen, colorReset)
	recommendationsCsvFile, err := runAIEngine(monitorOutputFile)
	if err != nil {
		fmt.Fprintf(os.Stderr, "%s%s%s: %s Falha: %v. Encerrando simulador.%s\n",
			colorRed, logPrefixAIEngine, colorReset, emojiFire, err, colorReset)
		os.Exit(1)
	}
	fmt.Printf("%s%s%s: --- %s%s%s finalizou, recomendações em: %s%s%s --- %s\n",
		colorCyan, logPrefixSimulator, colorReset, colorCyan, logPrefixAIEngine, colorGreen, colorPurple, recommendationsCsvFile, colorGreen, colorReset)

	fmt.Println("")
	fmt.Printf("%s%s%s: --- %s%s%s Iniciando --- %s\n", colorCyan, logPrefixSimulator, colorReset, colorCyan, logPrefixActuator, colorGreen, colorReset)
	err = runActuator(recommendationsCsvFile)
	if err != nil {
		fmt.Fprintf(os.Stderr, "%s%s%s: %s Falha: %v. Encerrando simulador.%s\n",
			colorRed, logPrefixActuator, colorReset, emojiFire, err, colorReset)
		os.Exit(1)
	}
	fmt.Printf("%s%s%s: --- %s%s%s finalizou --- %s\n", colorCyan, logPrefixSimulator, colorReset, colorCyan, logPrefixActuator, colorGreen, colorReset)

	fmt.Println("")
	fmt.Printf("%s%s%s: %s %s Simulador completou todas as etapas com sucesso! %s %s %s%s\n",
		colorGreen, logPrefixSimulator, colorReset,
		colorGreen, emojiRocket, emojiSuccess, emojiRocket, colorReset)
}
