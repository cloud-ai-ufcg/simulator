package main

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"sync"
	"time"

	"simulator/api"
	"simulator/constants"
	"simulator/utils"
)

func runExternalMonitorAndFetchOutput(_ time.Duration) (string, error) {
	forceKillMonitorProcesses()

	fmt.Printf("%s%s%s: %sIniciando monitor sem encerramento automático...%s\n",
		constants.ColorCyan, constants.LogPrefixMonitor, constants.ColorReset, constants.ColorBlue, constants.ColorReset)

	originalWd, err := os.Getwd()
	if err != nil {
		return "", fmt.Errorf("falha ao obter diretório de trabalho atual: %w", err)
	}

	if err := os.Chdir(constants.MonitorDirName); err != nil {
		return "", fmt.Errorf("falha ao mudar para o diretório %s: %w", constants.MonitorDirName, err)
	}
	defer os.Chdir(originalWd)

	cmd := exec.Command("make", "all")
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr

	if err := cmd.Start(); err != nil {
		return "", fmt.Errorf("falha ao iniciar 'make all': %w", err)
	}

	fmt.Printf("%s%s%s: %sMonitor iniciado (PID %d). Saída esperada em %s%s%s%s\n",
		constants.ColorCyan, constants.LogPrefixMonitor, constants.ColorReset, constants.ColorBlue, cmd.Process.Pid, constants.ColorPurple, constants.MonitorOutputBase, constants.ColorBlue, constants.ColorReset)

	go func() {
		err := cmd.Wait()
		if err != nil {
			fmt.Fprintf(os.Stderr, "%s%s%s: %sMonitor finalizou com erro: %v%s\n", constants.ColorCyan, constants.LogPrefixMonitor, constants.ColorReset, constants.ColorRed, err, constants.ColorReset)
		} else {
			fmt.Printf("%s%s%s: %sMonitor finalizou com sucesso.%s\n", constants.ColorCyan, constants.LogPrefixMonitor, constants.ColorReset, constants.ColorGreen, constants.ColorReset)
		}
	}()

	fullOutputPath := filepath.Clean(filepath.Join(constants.MonitorDirName, constants.MonitorOutputBase)) // Ajuste se necessário
	return fullOutputPath, nil
}

func forceKillMonitorProcesses() {
	fmt.Printf("%s%s%s: %sFinalizando processos antigos do monitor...%s\n", constants.ColorCyan, constants.LogPrefixMonitor, constants.ColorReset, constants.ColorBlue, constants.ColorReset)

	processesToKill := []struct {
		pattern string
	}{
		{pattern: "port-foward.sh"},
		{pattern: "kubectl.*port-forward"},
		{pattern: "./monitor"},
	}

	for _, proc := range processesToKill {
		cmd := exec.Command("pkill", "-f", proc.pattern)

		output, err := cmd.CombinedOutput()
		if err != nil {
			if !strings.Contains(string(output), "no process found") && !strings.Contains(string(output), "nenhum processo encontrado") { // Adicione outras variações se necessário
				fmt.Fprintf(os.Stderr, "%s%s%s: %sErro ao encerrar '%s': %v. Output: %s%s\n",
					constants.ColorCyan, constants.LogPrefixMonitor, constants.ColorReset, constants.ColorRed, proc.pattern, err, string(output), constants.ColorReset)
			}
		} else {
			fmt.Printf("%s%s%s: Processos correspondentes a '%s' encerrados (se existiam).%s\n",
				constants.ColorCyan, constants.LogPrefixMonitor, constants.ColorReset, proc.pattern, constants.ColorReset)
		}
	}
}

func runAIEngine() (string, error) {
	fmt.Printf("%s%s%s: %sIniciando AI-Engine.%s\n",
		constants.ColorCyan, constants.LogPrefixAIEngine, constants.ColorReset, constants.ColorBlue, constants.ColorReset)

	aiEngineTopDir := constants.AIEngineParentDirName

	recommendationsFileRel := constants.AIEngineOutputCSVPath

	makeTarget := "run-with-config"

	fmt.Printf("%s%s%s: %sExecutando via Makefile: %smake %s%s (CWD: %s%s%s)%s\n",
		constants.ColorCyan, constants.LogPrefixAIEngine, constants.ColorReset, constants.ColorBlue, constants.ColorPurple, makeTarget, constants.ColorBlue, constants.ColorPurple, aiEngineTopDir, constants.ColorBlue, constants.ColorReset)
	cmd := exec.Command("make", makeTarget)
	cmd.Dir = aiEngineTopDir
	cmdOutput, err := cmd.CombinedOutput()
	if err != nil {
		fmt.Printf("%s%s%s: %s%s--- %s%s%s ---%s\n", constants.ColorCyan, constants.LogPrefixAIEngine, constants.ColorReset, constants.ColorBlue, constants.ColorYellow, "AI-Engine Output Start (Error)", constants.ColorBlue, constants.ColorReset, constants.ColorReset)
		fmt.Print(string(cmdOutput))
		fmt.Printf("%s%s%s: %s%s--- %s%s%s ---%s\n", constants.ColorCyan, constants.LogPrefixAIEngine, constants.ColorReset, constants.ColorBlue, constants.ColorYellow, "AI-Engine Output End (Error)", constants.ColorBlue, constants.ColorReset, constants.ColorReset)
		fmt.Fprintf(os.Stderr, "%s%s%s: %sFalha ao executar Makefile target '%s%s%s': %v%s\n", constants.ColorCyan, constants.LogPrefixAIEngine, constants.ColorReset, constants.ColorBlue, constants.ColorPurple, makeTarget, constants.ColorRed, err, constants.ColorReset)
		return "", fmt.Errorf("falha ao executar Makefile target '%s': %w", makeTarget, err)
	}
	fmt.Printf("%s%s%s: %sMakefile target executado.%s\n", constants.ColorCyan, constants.LogPrefixAIEngine, constants.ColorReset, constants.ColorBlue, constants.ColorReset)
	fmt.Printf("%s%s%s: %s%s--- %s%s%s ---%s\n", constants.ColorCyan, constants.LogPrefixAIEngine, constants.ColorReset, constants.ColorBlue, constants.ColorGreen, "AI-Engine Output Start", constants.ColorBlue, constants.ColorReset, constants.ColorReset)
	fmt.Print(string(cmdOutput))

	fmt.Printf("%s%s%s: %s%s--- %s%s%s ---%s\n", constants.ColorCyan, constants.LogPrefixAIEngine, constants.ColorReset, constants.ColorBlue, constants.ColorGreen, "AI-Engine Output End", constants.ColorBlue, constants.ColorReset, constants.ColorReset)

	absRecommendationsFile, err := filepath.Abs(recommendationsFileRel)
	if err != nil {
		fmt.Fprintf(os.Stderr, "%s%s%s: %sErro ao obter caminho absoluto para %s%s%s: %v%s\n", constants.ColorCyan, constants.LogPrefixAIEngine, constants.ColorReset, constants.ColorBlue, constants.ColorPurple, recommendationsFileRel, constants.ColorRed, err, constants.ColorReset)
		return "", fmt.Errorf("erro ao obter caminho absoluto para %s: %w", recommendationsFileRel, err)
	}

	if _, err := os.Stat(absRecommendationsFile); os.IsNotExist(err) {
		fmt.Fprintf(os.Stderr, "%s%s%s: %sArquivo de recomendações esperado (%s%s%s) não foi encontrado após execução%s\n", constants.ColorCyan, constants.LogPrefixAIEngine, constants.ColorReset, constants.ColorBlue, constants.ColorPurple, absRecommendationsFile, constants.ColorReset, constants.ColorReset)
		return "", fmt.Errorf("arquivo de recomendações esperado (%s) não foi encontrado após execução", absRecommendationsFile)
	}

	fmt.Printf("%s%s%s: %sFinalizado. Recomendações esperadas em %s%s%s.%s\n",
		constants.ColorCyan, constants.LogPrefixAIEngine, constants.ColorReset, constants.ColorBlue, constants.ColorPurple, absRecommendationsFile, constants.ColorBlue, constants.ColorReset)
	return absRecommendationsFile, nil
}

func runActuator(recommendationsCsvFile string) error {
	fmt.Printf("%s%s%s: %sIniciando. Input CSV: %s%s%s%s\n",
		constants.ColorCyan, constants.LogPrefixActuator, constants.ColorReset, constants.ColorBlue, constants.ColorPurple, recommendationsCsvFile, constants.ColorBlue, constants.ColorReset)

	currentActuatorDir := constants.ActuatorDirName

	fmt.Printf("%s%s%s: %sExecutando programa Go: %s%s %s%s no diretório %s%s%s com input CSV %s%s%s%s\n",
		constants.ColorCyan, constants.LogPrefixActuator, constants.ColorReset, constants.ColorBlue, constants.ColorPurple, "go run main.go", recommendationsCsvFile, constants.ColorBlue, constants.ColorPurple, currentActuatorDir, constants.ColorBlue, constants.ColorPurple, recommendationsCsvFile, constants.ColorBlue, constants.ColorReset)

	cmd := exec.Command("go", "run", "main.go", recommendationsCsvFile)
	cmd.Dir = currentActuatorDir

	cmdOutput, err := cmd.CombinedOutput()
	if err != nil {
		fmt.Printf("%s%s%s: %sFalha ao executar programa Go (go run main.go %s%s%s em %s%s%s): %v%s\n",
			constants.ColorCyan, constants.LogPrefixActuator, constants.ColorReset, constants.ColorBlue, constants.ColorPurple, recommendationsCsvFile, constants.ColorBlue, constants.ColorPurple, currentActuatorDir, constants.ColorRed, err, constants.ColorReset)
		fmt.Printf("%s%s%s: %s%s--- %s%s%s ---%s\n", constants.ColorCyan, constants.LogPrefixActuator, constants.ColorReset, constants.ColorBlue, constants.ColorYellow, "Actuator Output Start (Error)", constants.ColorBlue, constants.ColorReset, constants.ColorReset)
		fmt.Print(string(cmdOutput))
		fmt.Printf("%s%s%s: %s%s--- %s%s%s ---%s\n", constants.ColorCyan, constants.LogPrefixActuator, constants.ColorReset, constants.ColorBlue, constants.ColorYellow, "Actuator Output End (Error)", constants.ColorBlue, constants.ColorReset, constants.ColorReset)
		fmt.Fprintf(os.Stderr, "%s%s%s: %sfalha ao executar programa Go: %v%s\n", constants.ColorCyan, constants.LogPrefixActuator, constants.ColorReset, constants.ColorRed, err, constants.ColorReset)
		return fmt.Errorf("falha ao executar programa Go com input %s: %w", recommendationsCsvFile, err)
	}

	fmt.Printf("%s%s%s: %sPrograma Go executado com sucesso.%s\n", constants.ColorCyan, constants.LogPrefixActuator, constants.ColorReset, constants.ColorBlue, constants.ColorReset)
	fmt.Printf("%s%s%s: %s%s--- %s%s%s ---%s\n", constants.ColorCyan, constants.LogPrefixActuator, constants.ColorReset, constants.ColorBlue, constants.ColorGreen, "Actuator Output Start", constants.ColorBlue, constants.ColorReset, constants.ColorReset)
	fmt.Print(string(cmdOutput))
	fmt.Printf("%s%s%s: %s%s--- %s%s%s ---%s\n", constants.ColorCyan, constants.LogPrefixActuator, constants.ColorReset, constants.ColorBlue, constants.ColorGreen, "Actuator Output End", constants.ColorBlue, constants.ColorReset, constants.ColorReset)
	fmt.Printf("%s%s%s: %sFinalizou a aplicação das recomendações.%s\n", constants.ColorCyan, constants.LogPrefixActuator, constants.ColorReset, constants.ColorBlue, constants.ColorReset)
	return nil
}

func main() {
	fmt.Println("")

	outputDir := "data/output"
	// Garante que o diretório existe antes de limpar
	if _, err := os.Stat(outputDir); os.IsNotExist(err) {
		if err := os.MkdirAll(outputDir, 0755); err != nil {
			fmt.Fprintf(os.Stderr, "Erro ao criar diretório de saída: %v\n", err)
			os.Exit(1)
		}
	}
	if err := utils.ClearOutputDir(outputDir); err != nil {
		fmt.Fprintf(os.Stderr, "Erro ao limpar diretório de saída: %v\n", err)
		os.Exit(1)
	}

	fmt.Println("Iniciando o ciclo de operações em paralelo...")

	var wg sync.WaitGroup
	engineErrChan := make(chan error, 1)
	monitorErrChan := make(chan error, 1)
	actuatorErrChan := make(chan error, 1)

	wg.Add(4)

	// 1. Broker via API
	go func() {
		defer wg.Done()
		apiURL := "http://localhost:8080/broker/"
		inputFilePath := "data/input_json.json" // Relativo à raiz do projeto
		if err := api.CallBrokerAPI(inputFilePath, apiURL); err != nil {
			fmt.Fprintf(os.Stderr, "%s%s%s: Erro ao chamar API do Broker: %v%s\n", constants.ColorCyan, constants.LogPrefixBroker, constants.ColorReset, err, constants.ColorReset)
		} else {
			fmt.Printf("%s%s%s: Broker finalizado com sucesso via API.%s\n", constants.ColorCyan, constants.LogPrefixBroker, constants.ColorReset, constants.ColorReset)
		}
	}()

	// 2. Monitor
	go func() {
		defer wg.Done()
		defer close(monitorErrChan)

		_, err := runExternalMonitorAndFetchOutput(10 * time.Second) // Duração é um exemplo
		if err != nil {
			monitorErrChan <- err
		}
	}()

	// 3. AI Engine (espera saída do monitor)
	go func() {
		defer wg.Done()
		defer close(engineErrChan)

		monitorOutputExpectedPath := filepath.Clean(filepath.Join(constants.MonitorDirName, constants.MonitorOutputBase))

		if err := utils.WaitForFile(monitorOutputExpectedPath, 30*time.Second); err != nil {
			engineErrChan <- fmt.Errorf("erro ao esperar saída do monitor (%s): %w", monitorOutputExpectedPath, err)
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

		recommendationsPath, err := filepath.Abs(constants.AIEngineOutputCSVPath)
		if err != nil {
			actuatorErrChan <- fmt.Errorf("erro ao obter caminho absoluto do CSV (%s): %w", constants.AIEngineOutputCSVPath, err)
			return
		}

		if err := utils.WaitForFile(recommendationsPath, 0); err != nil {
			actuatorErrChan <- fmt.Errorf("timeout aguardando saída do AI Engine (%s): %w", recommendationsPath, err)
			return
		}

		// Usar a API em vez do comando Go
		actuatorAPIURL := "http://localhost:8085/"
		if err := api.CallActuatorAPI(recommendationsPath, actuatorAPIURL); err != nil {
			actuatorErrChan <- fmt.Errorf("erro ao chamar API do Actuator: %w", err)
		}
	}()

	wg.Wait()

	// Finalização e tratamento de erros dos canais
	fmt.Println("\n--- Status Final das Operações ---")
	// Monitor
	select {
	case err, ok := <-monitorErrChan:
		if ok && err != nil {
			fmt.Fprintf(os.Stderr, "%s%s%s: Erro: %v%s\n", constants.ColorCyan, constants.LogPrefixMonitor, constants.ColorReset, err, constants.ColorReset)
		} else if ok {
			fmt.Printf("%s%s%s: Completado com sucesso.%s\n", constants.ColorCyan, constants.LogPrefixMonitor, constants.ColorReset, constants.ColorReset)
		} else {
			fmt.Printf("%s%s%s: Canal fechado sem erro explícito (pode ser normal).%s\n", constants.ColorCyan, constants.LogPrefixMonitor, constants.ColorReset, constants.ColorReset)
		}
	default:
		fmt.Printf("%s%s%s: Completado (verificar logs para detalhes).%s\n", constants.ColorCyan, constants.LogPrefixMonitor, constants.ColorReset, constants.ColorReset)
	}

	// AI Engine
	select {
	case err, ok := <-engineErrChan:
		if ok && err != nil {
			fmt.Fprintf(os.Stderr, "%s%s%s: Erro: %v%s\n", constants.ColorCyan, constants.LogPrefixAIEngine, constants.ColorReset, err, constants.ColorReset)
		} else if ok {
			fmt.Printf("%s%s%s: Completado com sucesso.%s\n", constants.ColorCyan, constants.LogPrefixAIEngine, constants.ColorReset, constants.ColorReset)
		} else {
			fmt.Printf("%s%s%s: Canal fechado sem erro explícito.%s\n", constants.ColorCyan, constants.LogPrefixAIEngine, constants.ColorReset, constants.ColorReset)
		}
	default:
		fmt.Printf("%s%s%s: Completado (verificar logs para detalhes).%s\n", constants.ColorCyan, constants.LogPrefixAIEngine, constants.ColorReset, constants.ColorReset)
	}

	// Actuator
	select {
	case err, ok := <-actuatorErrChan:
		if ok && err != nil {
			fmt.Fprintf(os.Stderr, "%s%s%s: Erro: %v%s\n", constants.ColorCyan, constants.LogPrefixActuator, constants.ColorReset, err, constants.ColorReset)
		} else if ok {
			fmt.Printf("%s%s%s: Completado com sucesso.%s\n", constants.ColorCyan, constants.LogPrefixActuator, constants.ColorReset, constants.ColorReset)
		} else {
			fmt.Printf("%s%s%s: Canal fechado sem erro explícito.%s\n", constants.ColorCyan, constants.LogPrefixActuator, constants.ColorReset, constants.ColorReset)
		}
	default:
		fmt.Printf("%s%s%s: Completado (verificar logs para detalhes).%s\n", constants.ColorCyan, constants.LogPrefixActuator, constants.ColorReset, constants.ColorReset)
	}

	fmt.Println("\nCiclo de execução paralelo encerrado.")
}
