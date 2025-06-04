package main

import (
	"fmt"
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

const (
	logPrefixSimulator = " Simulador"
	logPrefixBroker    = " Broker"
	logPrefixMonitor   = " Monitor"
	logPrefixAIEngine  = " AI-Engine"
	logPrefixActuator  = " Actuator"
)

// Paths and names (existing constants)
const (
	monitorDirName    = "monitor"
	monitorOutputBase = "../data/output/monitor_outputs.json"

	aiEngineParentDirName = "ai-engine"
	aiEngineWorkSubDir    = "engine"
	aiEngineOutputCSVPath = "data/output/recommendations.csv"

	actuatorDirName      = "actuator"
	actuatorInputCSVName = "recommendations.csv"

	brokerInputDataCSVPath    = "data/recorte_5min.csv"
	brokerInputConfigYAMLPath = "data/config.yaml"
)

func forceKillMonitorProcesses() {
	fmt.Printf("%s%s%s: %sForçando encerramento de processos antigos do monitor...%s\n", colorCyan, logPrefixMonitor, colorReset, colorBlue, colorReset)
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
				fmt.Printf("%s%s%s: %sErro ao tentar forçar o encerramento de '%s%s%s': %s%v%s. %sOutput: %s%s%s%s\n",
					colorCyan, logPrefixMonitor, colorReset, colorBlue, colorPurple, proc.pattern, colorBlue, colorRed, err, colorBlue, colorBlue, colorRed, string(output), colorBlue, colorReset)
			}
		} else {
			fmt.Printf("%s%s%s: %sSinal KILL enviado com sucesso para processos correspondentes a '%s%s%s'. %sOutput: %s%s%s%s\n",
				colorCyan, logPrefixMonitor, colorReset, colorBlue, colorPurple, proc.name, colorBlue, colorBlue, colorGreen, string(output), colorBlue, colorReset)
		}
	}
	time.Sleep(100 * time.Millisecond)
}

func runExternalMonitorAndFetchOutput(duration time.Duration) (string, error) {
	forceKillMonitorProcesses()

	fmt.Printf("%s%s%s: %sIniciando...%s\n", colorCyan, logPrefixMonitor, colorReset, colorBlue, colorReset)

	originalWd, err := os.Getwd()
	if err != nil {
		fmt.Fprintf(os.Stderr, "%s%s%s: %sFalha ao obter diretório de trabalho atual: %v%s\n", colorCyan, logPrefixMonitor, colorReset, colorRed, err, colorReset)
		return "", fmt.Errorf("falha ao obter diretório de trabalho atual: %w", err)
	}

	if err := os.Chdir(monitorDirName); err != nil {
		fmt.Fprintf(os.Stderr, "%s%s%s: %sFalha ao mudar para o diretório %s%s%s: %v%s\n", colorCyan, logPrefixMonitor, colorReset, colorBlue, colorPurple, monitorDirName, colorRed, err, colorReset)
		return "", fmt.Errorf("falha ao mudar para o diretório %s: %w", monitorDirName, err)
	}
	defer func() {
		fmt.Printf("%s%s%s: %sVoltando para o diretório original %s%s%s...%s\n",
			colorCyan, logPrefixMonitor, colorReset, colorBlue, colorPurple, originalWd, colorBlue, colorReset)
		if err := os.Chdir(originalWd); err != nil {
			fmt.Fprintf(os.Stderr, "%s%s%s: %sCRÍTICO - Falha ao voltar para o diretório original %s%s%s: %v. %sEncerrando.%s\n",
				colorCyan, logPrefixMonitor, colorReset, colorBlue, colorPurple, originalWd, colorRed, err, colorBlue, colorReset)
			os.Exit(1)
		}
	}()

	fmt.Printf("%s%s%s: %sExecutando 'make all' em %s%s%s por %s%v%s...%s\n",
		colorCyan, logPrefixMonitor, colorReset, colorBlue, colorPurple, monitorDirName, colorBlue, colorPurple, duration, colorBlue, colorReset)
	cmd := exec.Command("make", "all")

	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr

	if err := cmd.Start(); err != nil {
		fmt.Fprintf(os.Stderr, "%s%s%s: %sFalha ao iniciar 'make all': %v%s\n", colorCyan, logPrefixMonitor, colorReset, colorRed, err, colorReset)
		return "", fmt.Errorf("falha ao iniciar 'make all': %w", err)
	}

	fmt.Printf("%s%s%s: %sProcesso iniciado (PID %s%d%s), aguardando %s%v%s...%s\n",
		colorCyan, logPrefixMonitor, colorReset, colorBlue, colorPurple, cmd.Process.Pid, colorBlue, colorPurple, duration, colorBlue, colorReset)
	time.Sleep(duration)

	fmt.Printf("%s%s%s: %sDuração esgotada. Enviando sinal de interrupção para 'make all'...%s\n",
		colorCyan, logPrefixMonitor, colorReset, colorBlue, colorReset)
	if err := cmd.Process.Signal(os.Interrupt); err != nil {
		fmt.Printf("%s%s%s: %sFalha ao enviar sinal de interrupção: %v. %sTentando aguardar processo.%s\n",
			colorCyan, logPrefixMonitor, colorReset, colorRed, err, colorBlue, colorReset)
	}

	fmt.Printf("%s%s%s: %sAguardando 'make all' completar limpeza e sair...%s\n",
		colorCyan, logPrefixMonitor, colorReset, colorBlue, colorReset)

	waitChan := make(chan error, 1)
	go func() {
		waitChan <- cmd.Wait()
	}()

	select {
	case err := <-waitChan:
		if err != nil {
			if exitErr, ok := err.(*exec.ExitError); ok {
				fmt.Printf("%s%s%s: %s'make all' saiu com erro após interrupção: %v. %sStderr: %s%s%s\n",
					colorCyan, logPrefixMonitor, colorReset, colorRed, exitErr, colorBlue, colorRed, string(exitErr.Stderr), colorReset)
			} else {
				fmt.Printf("%s%s%s: %s'make all' falhou ao completar após interrupção: %v%s\n",
					colorCyan, logPrefixMonitor, colorReset, colorRed, err, colorReset)
			}
		} else {
			fmt.Printf("%s%s%s: %s'make all' completado com sucesso após interrupção.%s\n",
				colorCyan, logPrefixMonitor, colorReset, colorBlue, colorReset)
		}
	case <-time.After(5 * time.Second):
		fmt.Printf("%s%s%s: %s'make all' não saiu prontamente após interrupção. Enviando sinal KILL...%s\n",
			colorCyan, logPrefixMonitor, colorReset, colorBlue, colorReset)
		if killErr := cmd.Process.Kill(); killErr != nil {
			fmt.Printf("%s%s%s: %sFalha ao enviar sinal KILL: %v%s\n",
				colorCyan, logPrefixMonitor, colorReset, colorRed, killErr, colorReset)
			<-waitChan
			fmt.Fprintf(os.Stderr, "%s%s%s: %sFalha ao matar processo 'make all' após timeout: %v%s\n", colorCyan, logPrefixMonitor, colorReset, colorRed, killErr, colorReset)
			return "", fmt.Errorf("falha ao matar processo 'make all' após timeout: %w", killErr)
		}
		finalWaitErr := <-waitChan
		fmt.Printf("%s%s%s: %sProcesso 'make all' morto. Resultado do Wait: %v%s\n",
			colorCyan, logPrefixMonitor, colorReset, colorRed, finalWaitErr, colorReset)
	}

	forceKillMonitorProcesses()

	originalMonitorOutputPath := monitorOutputBase
	fullOriginalMonitorPath := filepath.Join(originalWd, monitorDirName, monitorOutputBase)

	fmt.Printf("%s%s%s: %sVerificando arquivo de saída do monitor em %s%s%s (dentro de %s%s%s)...%s\n",
		colorCyan, logPrefixMonitor, colorReset, colorBlue, colorPurple, originalMonitorOutputPath, colorBlue, colorPurple, monitorDirName, colorBlue, colorReset)
	if _, err := os.Stat(originalMonitorOutputPath); os.IsNotExist(err) {
		fmt.Fprintf(os.Stderr, "%s%s%s: %sArquivo de saída do monitor %s%s%s não encontrado em %s%s%s após execução: %v%s\n", colorCyan, logPrefixMonitor, colorReset, colorBlue, colorPurple, originalMonitorOutputPath, colorBlue, colorPurple, monitorDirName, colorRed, err, colorReset)
		return "", fmt.Errorf("arquivo de saída do monitor %s não encontrado em %s após execução: %w", originalMonitorOutputPath, monitorDirName, err)
	}

	returnedPath := filepath.Join(monitorDirName, monitorOutputBase)
	fmt.Printf("%s%s%s: %sMonitor finalizado. Saída disponível em %s%s%s.%s\n",
		colorCyan, logPrefixMonitor, colorReset, colorBlue, colorPurple, fullOriginalMonitorPath, colorBlue, colorReset)
	return returnedPath, nil
}

func runAIEngine() (string, error) {
	fmt.Printf("%s%s%s: %sIniciando AI-Engine.%s\n",
		colorCyan, logPrefixAIEngine, colorReset, colorBlue, colorReset)

	aiEngineTopDir := aiEngineParentDirName

	recommendationsFileRel := aiEngineOutputCSVPath

	makeTarget := "run-with-config"

	fmt.Printf("%s%s%s: %sExecutando via Makefile: %smake %s%s (CWD: %s%s%s)%s\n",
		colorCyan, logPrefixAIEngine, colorReset, colorBlue, colorPurple, makeTarget, colorBlue, colorPurple, aiEngineTopDir, colorBlue, colorReset)
	cmd := exec.Command("make", makeTarget) // CONFIG_FILE não é mais passado
	cmd.Dir = aiEngineTopDir

	cmdOutput, err := cmd.CombinedOutput()
	if err != nil {
		fmt.Printf("%s%s%s: %s%s--- %s%s%s ---%s\n", colorCyan, logPrefixAIEngine, colorReset, colorBlue, colorYellow, "AI-Engine Output Start (Error)", colorBlue, colorReset, colorReset)
		fmt.Print(string(cmdOutput)) // Raw output, no extra newline
		fmt.Printf("%s%s%s: %s%s--- %s%s%s ---%s\n", colorCyan, logPrefixAIEngine, colorReset, colorBlue, colorYellow, "AI-Engine Output End (Error)", colorBlue, colorReset, colorReset)
		fmt.Fprintf(os.Stderr, "%s%s%s: %sFalha ao executar Makefile target '%s%s%s': %v%s\n", colorCyan, logPrefixAIEngine, colorReset, colorBlue, colorPurple, makeTarget, colorRed, err, colorReset)
		return "", fmt.Errorf("falha ao executar Makefile target '%s': %w", makeTarget, err)
	}
	fmt.Printf("%s%s%s: %sMakefile target executado.%s\n", colorCyan, logPrefixAIEngine, colorReset, colorBlue, colorReset)
	fmt.Printf("%s%s%s: %s%s--- %s%s%s ---%s\n", colorCyan, logPrefixAIEngine, colorReset, colorBlue, colorGreen, "AI-Engine Output Start", colorBlue, colorReset, colorReset)
	fmt.Print(string(cmdOutput)) // Raw output, no extra newline
	fmt.Printf("%s%s%s: %s%s--- %s%s%s ---%s\n", colorCyan, logPrefixAIEngine, colorReset, colorBlue, colorGreen, "AI-Engine Output End", colorBlue, colorReset, colorReset)

	absRecommendationsFile, err := filepath.Abs(recommendationsFileRel)
	if err != nil {
		fmt.Fprintf(os.Stderr, "%s%s%s: %sErro ao obter caminho absoluto para %s%s%s: %v%s\n", colorCyan, logPrefixAIEngine, colorReset, colorBlue, colorPurple, recommendationsFileRel, colorRed, err, colorReset)
		return "", fmt.Errorf("erro ao obter caminho absoluto para %s: %w", recommendationsFileRel, err)
	}

	if _, err := os.Stat(absRecommendationsFile); os.IsNotExist(err) {
		fmt.Fprintf(os.Stderr, "%s%s%s: %sArquivo de recomendações esperado (%s%s%s) não foi encontrado após execução%s\n", colorCyan, logPrefixAIEngine, colorReset, colorBlue, colorPurple, absRecommendationsFile, colorReset, colorReset)
		return "", fmt.Errorf("arquivo de recomendações esperado (%s) não foi encontrado após execução", absRecommendationsFile)
	}

	fmt.Printf("%s%s%s: %sFinalizado. Recomendações esperadas em %s%s%s.%s\n",
		colorCyan, logPrefixAIEngine, colorReset, colorBlue, colorPurple, absRecommendationsFile, colorBlue, colorReset)
	return absRecommendationsFile, nil
}

func runActuator(recommendationsCsvFile string) error {
	fmt.Printf("%s%s%s: %sIniciando. Input CSV: %s%s%s%s\n",
		colorCyan, logPrefixActuator, colorReset, colorBlue, colorPurple, recommendationsCsvFile, colorBlue, colorReset)

	currentActuatorDir := actuatorDirName

	// A cópia do arquivo para o diretório do atuador foi removida.
	// O caminho absoluto do CSV será passado diretamente como argumento.

	fmt.Printf("%s%s%s: %sExecutando programa Go: %s%s %s%s no diretório %s%s%s com input CSV %s%s%s%s\n",
		colorCyan, logPrefixActuator, colorReset, colorBlue, colorPurple, "go run main.go", recommendationsCsvFile, colorBlue, colorPurple, currentActuatorDir, colorBlue, colorPurple, recommendationsCsvFile, colorBlue, colorReset)

	cmd := exec.Command("go", "run", "main.go", recommendationsCsvFile) // Passa o caminho do CSV como argumento
	cmd.Dir = currentActuatorDir

	cmdOutput, err := cmd.CombinedOutput()
	if err != nil {
		fmt.Printf("%s%s%s: %sFalha ao executar programa Go (go run main.go %s%s%s em %s%s%s): %v%s\n",
			colorCyan, logPrefixActuator, colorReset, colorBlue, colorPurple, recommendationsCsvFile, colorBlue, colorPurple, currentActuatorDir, colorRed, err, colorReset)
		fmt.Printf("%s%s%s: %s%s--- %s%s%s ---%s\n", colorCyan, logPrefixActuator, colorReset, colorBlue, colorYellow, "Actuator Output Start (Error)", colorBlue, colorReset, colorReset)
		fmt.Print(string(cmdOutput)) // Raw output, no extra newline
		fmt.Printf("%s%s%s: %s%s--- %s%s%s ---%s\n", colorCyan, logPrefixActuator, colorReset, colorBlue, colorYellow, "Actuator Output End (Error)", colorBlue, colorReset, colorReset)
		fmt.Fprintf(os.Stderr, "%s%s%s: %sfalha ao executar programa Go: %v%s\n", colorCyan, logPrefixActuator, colorReset, colorRed, err, colorReset)
		return fmt.Errorf("falha ao executar programa Go com input %s: %w", recommendationsCsvFile, err)
	}

	fmt.Printf("%s%s%s: %sPrograma Go executado com sucesso.%s\n", colorCyan, logPrefixActuator, colorReset, colorBlue, colorReset)
	fmt.Printf("%s%s%s: %s%s--- %s%s%s ---%s\n", colorCyan, logPrefixActuator, colorReset, colorBlue, colorGreen, "Actuator Output Start", colorBlue, colorReset, colorReset)
	fmt.Print(string(cmdOutput)) // Raw output, no extra newline
	fmt.Printf("%s%s%s: %s%s--- %s%s%s ---%s\n", colorCyan, logPrefixActuator, colorReset, colorBlue, colorGreen, "Actuator Output End", colorBlue, colorReset, colorReset)
	fmt.Printf("%s%s%s: %sFinalizou a aplicação das recomendações.%s\n", colorCyan, logPrefixActuator, colorReset, colorBlue, colorReset)
	return nil
}

func main() {
	fmt.Println("")
	fmt.Printf("%s%s%s: %sIniciando o ciclo de operações...%s\n", colorCyan, logPrefixSimulator, colorReset, colorBlue, colorReset)

	csvPath := brokerInputDataCSVPath
	yamlPath := brokerInputConfigYAMLPath

	configYaml, err := os.Open(yamlPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "%s%s%s: %sFalha ao abrir configuração YAML %s%s%s: %v%s\n",
			colorRed, logPrefixSimulator, colorReset, colorBlue, colorPurple, yamlPath, colorRed, err, colorReset)
		os.Exit(1)
	}

	csvData, err := os.Open(csvPath)
	if err != nil {
		fmt.Println("")
		fmt.Fprintf(os.Stderr, "%s%s%s: %sFalha ao abrir dados CSV %s%s%s: %v%s\n",
			colorRed, logPrefixSimulator, colorReset, colorBlue, colorPurple, csvPath, colorRed, err, colorReset)
		os.Exit(1)
	}

	fmt.Println("")
	fmt.Printf("%s%s%s: %s--- %s%s%s%s Iniciando %s--- %s\n", colorCyan, logPrefixSimulator, colorReset, colorBlue, colorCyan, logPrefixBroker, colorGreen, colorBlue, colorBlue, colorReset)
	broker.Run(csvData, configYaml)
	csvData.Close()
	configYaml.Close()
	fmt.Printf("%s%s%s: %s--- %s%s%s%s finalizado %s--- %s\n", colorCyan, logPrefixSimulator, colorReset, colorBlue, colorCyan, logPrefixBroker, colorGreen, colorBlue, colorBlue, colorReset)

	fmt.Println("")
	fmt.Printf("%s%s%s: %s--- %s%s%s%s Iniciando %s--- %s\n", colorCyan, logPrefixSimulator, colorReset, colorBlue, colorCyan, logPrefixMonitor, colorGreen, colorBlue, colorBlue, colorReset)
	monitorOutputFile, err := runExternalMonitorAndFetchOutput(10 * time.Second)
	if err != nil {
		fmt.Fprintf(os.Stderr, "%s%s%s: %sFalha: %v. %sEncerrando simulador.%s\n",
			colorRed, logPrefixMonitor, colorReset, colorRed, err, colorBlue, colorReset)
		os.Exit(1)
	}
	fmt.Printf("%s%s%s: %s--- %s%s%s%s Output em: %s%s%s%s --- %s\n",
		colorCyan, logPrefixSimulator, colorReset, colorBlue, colorCyan, logPrefixMonitor, colorGreen, colorBlue, colorPurple, monitorOutputFile, colorGreen, colorBlue, colorReset)

	fmt.Println("")
	fmt.Printf("%s%s%s: %s--- %s%s%s%s Iniciando %s--- %s\n", colorCyan, logPrefixSimulator, colorReset, colorBlue, colorCyan, logPrefixAIEngine, colorGreen, colorBlue, colorBlue, colorReset)
	recommendationsCsvFile, err := runAIEngine()
	if err != nil {
		fmt.Fprintf(os.Stderr, "%s%s%s: %sFalha: %v. %sEncerrando simulador.%s\n",
			colorRed, logPrefixAIEngine, colorReset, colorRed, err, colorBlue, colorReset)
		os.Exit(1)
	}
	fmt.Printf("%s%s%s: %s--- %s%s%s%s finalizou, recomendações em: %s%s%s%s --- %s\n",
		colorCyan, logPrefixSimulator, colorReset, colorBlue, colorCyan, logPrefixAIEngine, colorGreen, colorBlue, colorPurple, recommendationsCsvFile, colorGreen, colorBlue, colorReset)

	fmt.Println("")
	fmt.Printf("%s%s%s: %s--- %s%s%s%s Iniciando %s--- %s\n", colorCyan, logPrefixSimulator, colorReset, colorBlue, colorCyan, logPrefixActuator, colorGreen, colorBlue, colorBlue, colorReset)
	err = runActuator(recommendationsCsvFile)
	if err != nil {
		fmt.Fprintf(os.Stderr, "%s%s%s: %sFalha: %v. %sEncerrando simulador.%s\n",
			colorRed, logPrefixActuator, colorReset, colorRed, err, colorBlue, colorReset)
		os.Exit(1)
	}
	fmt.Printf("%s%s%s: %s--- %s%s%s%s finalizou %s--- %s\n", colorCyan, logPrefixSimulator, colorReset, colorBlue, colorCyan, logPrefixActuator, colorGreen, colorBlue, colorBlue, colorReset)

	fmt.Println("")
}
