package main

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"time"
	"sync"
	"strings"

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

func waitForFile(path string, timeout time.Duration) error {
	fmt.Printf("%s%s%s: %sAguardando arquivo %s%s%s aparecer...%s\n",
		colorCyan, logPrefixSimulator, colorReset, colorBlue, colorPurple, path, colorBlue, colorReset)

	start := time.Now()
	for {
		if _, err := os.Stat(path); err == nil {
			fmt.Printf("%s%s%s: %sArquivo detectado: %s%s%s após %v.%s\n",
				colorCyan, logPrefixSimulator, colorReset, colorGreen, colorPurple, path, colorGreen, time.Since(start), colorReset)
			return nil
		}

		if timeout > 0 && time.Since(start) > timeout {
			return fmt.Errorf("tempo limite ao esperar pelo arquivo: %s", path)
		}

		time.Sleep(500 * time.Millisecond)
	}
}



func runExternalMonitorAndFetchOutput(_ time.Duration) (string, error) {
	forceKillMonitorProcesses()

	fmt.Printf("%s%s%s: %sIniciando monitor sem encerramento automático...%s\n",
		colorCyan, logPrefixMonitor, colorReset, colorBlue, colorReset)

	originalWd, err := os.Getwd()
	if err != nil {
		return "", fmt.Errorf("falha ao obter diretório de trabalho atual: %w", err)
	}

	if err := os.Chdir(monitorDirName); err != nil {
		return "", fmt.Errorf("falha ao mudar para o diretório %s: %w", monitorDirName, err)
	}
	defer os.Chdir(originalWd)

	cmd := exec.Command("make", "all")
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr

	if err := cmd.Start(); err != nil {
		return "", fmt.Errorf("falha ao iniciar 'make all': %w", err)
	}

	fmt.Printf("%s%s%s: %sMonitor iniciado (PID %d). Saída esperada em %s%s%s%s\n",
		colorCyan, logPrefixMonitor, colorReset, colorBlue, cmd.Process.Pid, colorPurple, monitorOutputBase, colorBlue, colorReset)

	// Opcional: pode deixar rodando em segundo plano
	go func() {
		err := cmd.Wait()
		if err != nil {
			fmt.Fprintf(os.Stderr, "%s%s%s: %sMonitor finalizou com erro: %v%s\n", colorCyan, logPrefixMonitor, colorReset, colorRed, err, colorReset)
		} else {
			fmt.Printf("%s%s%s: %sMonitor finalizou com sucesso.%s\n", colorCyan, logPrefixMonitor, colorReset, colorGreen, colorReset)
		}
	}()

	fullOutputPath := filepath.Join(monitorDirName, monitorOutputBase)
	return fullOutputPath, nil
}

func forceKillMonitorProcesses() {
	fmt.Printf("%s%s%s: %sFinalizando processos antigos do monitor...%s\n", colorCyan, logPrefixMonitor, colorReset, colorBlue, colorReset)

	processesToKill := []struct {
		pattern string
	}{
		{pattern: "port-foward.sh"},
		{pattern: "kubectl.*port-forward"},
		{pattern: "./monitor"},
	}

	for _, proc := range processesToKill {
		cmd := exec.Command("pkill", "-f", proc.pattern)
		if output, err := cmd.CombinedOutput(); err != nil {
			if !strings.Contains(string(output), "no process found") {
				fmt.Fprintf(os.Stderr, "%s%s%s: %sErro ao encerrar '%s': %v\n", colorCyan, logPrefixMonitor, colorReset, colorRed, proc.pattern, err)
			}
		}
	}
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

func clearOutputDir(path string) error {
	fmt.Printf("%s%s%s: %sLimpando diretório de saída: %s%s%s...%s\n",
		colorCyan, logPrefixSimulator, colorReset, colorBlue, colorPurple, path, colorBlue, colorReset)

	dirEntries, err := os.ReadDir(path)
	if err != nil {
		return fmt.Errorf("erro ao ler diretório %s: %w", path, err)
	}

	for _, entry := range dirEntries {
		fullPath := filepath.Join(path, entry.Name())
		if err := os.RemoveAll(fullPath); err != nil {
			return fmt.Errorf("erro ao remover %s: %w", fullPath, err)
		}
	}
	fmt.Printf("%s%s%s: %sDiretório %s%s%s limpo com sucesso.%s\n",
		colorCyan, logPrefixSimulator, colorReset, colorGreen, colorPurple, path, colorGreen, colorReset)
	return nil
}

func main() {
	fmt.Println("")

	outputDir := "data/output"
	if err := clearOutputDir(outputDir); err != nil {
		fmt.Fprintf(os.Stderr, "%s%s%s: %sErro ao limpar diretório de saída: %v%s\n",
			colorCyan, logPrefixSimulator, colorReset, colorRed, err, colorReset)
		os.Exit(1)
	}

	fmt.Printf("%s%s%s: %sIniciando o ciclo de operações em paralelo...%s\n", colorCyan, logPrefixSimulator, colorReset, colorBlue, colorReset)
	
	var wg sync.WaitGroup
	engineErrChan := make(chan error, 1)
	monitorErrChan := make(chan error, 1)
	actuatorErrChan := make(chan error, 1)

	wg.Add(4)

	// 1. Broker
	go func() {
		defer wg.Done()
		fmt.Printf("%s%s%s: %sExecutando broker...%s\n", colorCyan, logPrefixBroker, colorReset, colorBlue, colorReset)
		csvData, err1 := os.Open(brokerInputDataCSVPath)
		configYaml, err2 := os.Open(brokerInputConfigYAMLPath)
		if err1 != nil || err2 != nil {
			fmt.Fprintf(os.Stderr, "Erro ao abrir arquivos: %v %v\n", err1, err2)
			return
		}
		defer csvData.Close()
		defer configYaml.Close()
		broker.Run(csvData, configYaml)
		fmt.Printf("%s%s%s: %sBroker finalizado com sucesso.%s\n", colorCyan, logPrefixBroker, colorReset, colorBlue, colorReset)
	}()

	// 2. Monitor
	go func() {
		defer wg.Done()
		defer close(monitorErrChan)

		_, err := runExternalMonitorAndFetchOutput(10 * time.Second)
		if err != nil {
			monitorErrChan <- err
		}
	}()

	// 3. AI Engine (espera saída do monitor)
	go func() {
		defer wg.Done()
		defer close(engineErrChan)

		monitorOutputPath := filepath.Clean(filepath.Join(monitorDirName, monitorOutputBase))
		if err := waitForFile(monitorOutputPath, 30*time.Second); err != nil {
			engineErrChan <- fmt.Errorf("erro ao esperar saída do monitor: %w", err)
			return
		}

		if _, err := runAIEngine(); err != nil {
			engineErrChan <- err
		}
	}()

	// 4. Actuator (espera arquivo CSV)
	go func() {
		defer wg.Done()
		defer close(actuatorErrChan)

		recommendationsPath, err := filepath.Abs(aiEngineOutputCSVPath)
		if err != nil {
			actuatorErrChan <- fmt.Errorf("erro ao obter caminho absoluto do CSV: %w", err)
			return
		}


		if err := waitForFile(recommendationsPath, 0); err != nil {
			actuatorErrChan <- fmt.Errorf("timeout aguardando saída do AI Engine: %w", err)
			return
		}

		if err := runActuator(recommendationsPath); err != nil {
			actuatorErrChan <- err
		}
	}()

	wg.Wait()

	// Finalização
	
	// Monitor
	select {
	case err, ok := <-monitorErrChan:
		if ok && err != nil {
			fmt.Fprintf(os.Stderr, "Erro no monitor: %v\n", err)
		} else {
			fmt.Println("Monitor completado com sucesso.")
		}
	default:
		fmt.Println("Monitor completado com sucesso.")
	}

	// AI Engine
	select {
	case err, ok := <-engineErrChan:
		if ok && err != nil {
			fmt.Fprintf(os.Stderr, "Erro no AI Engine: %v\n", err)
		} else {
			fmt.Println("AI Engine completado com sucesso.")
		}
	default:
		fmt.Println("AI Engine completado com sucesso.")
	}

	// Actuator
	select {
	case err, ok := <-actuatorErrChan:
		if ok && err != nil {
			fmt.Fprintf(os.Stderr, "Erro no actuator: %v\n", err)
		} else {
			fmt.Println("Actuator completado com sucesso.")
		}
	default:
		fmt.Println("Actuator completado com sucesso.")
	}

	fmt.Printf("%s%s%s: %sCiclo de execução paralelo encerrado.%s\n", colorCyan, logPrefixSimulator, colorReset, colorBlue, colorReset)
}
