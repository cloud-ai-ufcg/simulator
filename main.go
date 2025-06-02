package main

import (
	"encoding/json"
	"fmt"
	"log"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"

	"github.com/cloud-ai-ufcg/broker/broker"
)

// forceKillMonitorProcesses attempts to forcefully kill known monitor-related processes.
func forceKillMonitorProcesses() {
	log.Println("External Monitor: Forcefully killing any old monitor-related processes...")
	processesToKill := []struct {
		name    string
		pattern string
	}{
		{"port-foward.sh", "port-foward.sh"},
		{"kubectl port-forward", "kubectl.*port-forward"},
		{"./monitor executable", "./monitor"}, // In case the monitor itself lingers
	}

	for _, proc := range processesToKill {
		cmd := exec.Command("pkill", "-KILL", "-f", proc.pattern)
		output, err := cmd.CombinedOutput()
		if err != nil {
			if strings.Contains(string(output), "no process found") || strings.Contains(err.Error(), "exit status 1") {
				log.Printf("External Monitor: No processes found matching '%s' or already killed.", proc.name)
			} else {
				log.Printf("External Monitor: Error trying to pkill -KILL -f '%s': %v, Output: %s", proc.pattern, err, string(output))
			}
		} else {
			log.Printf("External Monitor: Successfully sent KILL signal to processes matching '%s'. Output: %s", proc.name, string(output))
		}
	}
	// Give a very short time for OS to reap killed processes
	time.Sleep(100 * time.Millisecond)
}

// runExternalMonitorAndFetchOutput executes the external monitor using its Makefile,
// lets it run for a specified duration, stops it, and copies its output.
func runExternalMonitorAndFetchOutput(duration time.Duration) (string, error) {
	// Aggressive cleanup before starting
	forceKillMonitorProcesses()

	fmt.Println("External Monitor: Starting...")
	monitorDir := "monitor" // Relative path to the monitor's directory
	monitorOutputFileName := "monitor_outputs.json"
	simulatorDestOutputFileName := "monitor_output.json"

	// Get current working directory to return to it later
	originalWd, err := os.Getwd()
	if err != nil {
		return "", fmt.Errorf("External Monitor: failed to get current working directory: %w", err)
	}

	// Change to the monitor's directory to run make
	if err := os.Chdir(monitorDir); err != nil {
		return "", fmt.Errorf("External Monitor: failed to change directory to %s: %w", monitorDir, err)
	}
	// Ensure we change back to the original directory
	defer func() {
		if err := os.Chdir(originalWd); err != nil {
			log.Printf("External Monitor: CRITICAL - failed to change back to original directory %s: %v", originalWd, err)
		}
	}()

	fmt.Printf("External Monitor: Running 'make all' in %s for %v...\n", monitorDir, duration)
	cmd := exec.Command("make", "all")
	// cmd.Dir is not strictly necessary here as we already changed dir, but doesn't hurt.
	// cmd.Dir = monitorDir

	// Capture output for debugging
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr

	if err := cmd.Start(); err != nil {
		return "", fmt.Errorf("External Monitor: failed to start 'make all': %w", err)
	}

	fmt.Printf("External Monitor: Process started (PID %d), waiting for %v...\n", cmd.Process.Pid, duration)
	time.Sleep(duration)

	fmt.Println("External Monitor: Duration elapsed. Sending interrupt signal to 'make all' process...")
	if err := cmd.Process.Signal(os.Interrupt); err != nil {
		// Log the error but try to proceed with cmd.Wait() as the process might have exited already or signal failed
		log.Printf("External Monitor: Failed to send interrupt signal: %v. Attempting to wait for process.", err)
	}

	fmt.Println("External Monitor: Waiting for 'make all' to complete cleanup and exit...")

	// Wait for the command to exit, but with a timeout for the wait itself.
	waitChan := make(chan error, 1)
	go func() {
		waitChan <- cmd.Wait() // This will block until the command exits
	}()

	select {
	case err := <-waitChan:
		// Process exited (or an error occurred starting/waiting for it)
		if err != nil {
			if exitErr, ok := err.(*exec.ExitError); ok {
				log.Printf("External Monitor: 'make all' exited with error after interrupt: %v. Stderr: %s", exitErr, string(exitErr.Stderr))
			} else {
				log.Printf("External Monitor: 'make all' failed to complete after interrupt: %v", err)
			}
		} else {
			fmt.Println("External Monitor: 'make all' completed successfully after interrupt.")
		}
	case <-time.After(5 * time.Second): // 5-second timeout for cmd.Wait()
		log.Println("External Monitor: 'make all' did not exit promptly after interrupt. Sending kill signal...")
		if killErr := cmd.Process.Kill(); killErr != nil {
			log.Printf("External Monitor: Failed to send kill signal: %v", killErr)
			// If kill fails, we might be in a bad state, but we must try to unblock.
			// We still need to wait for the process to be reaped after kill.
			<-waitChan // Drain the channel, wait for the goroutine to finish
			return "", fmt.Errorf("External Monitor: failed to kill 'make all' process after timeout: %w", killErr)
		}
		// After sending kill, Wait() should unblock. Drain the channel.
		finalWaitErr := <-waitChan
		log.Printf("External Monitor: 'make all' process killed. Wait result: %v", finalWaitErr)
	}

	// Aggressive cleanup after attempting to stop/kill
	forceKillMonitorProcesses()

	// Define paths relative to the original working directory for the copy
	// The monitor_outputs.json is created inside the 'monitor' directory by its makefile/program
	sourcePathInMonitorDir := monitorOutputFileName
	// Destination is in the simulator's root
	destPathInSimulatorRoot := filepath.Join(originalWd, simulatorDestOutputFileName)
	// Source path from originalWd's perspective
	absSourcePath := filepath.Join(originalWd, monitorDir, sourcePathInMonitorDir)

	fmt.Printf("External Monitor: Copying output from %s to %s...\n", absSourcePath, destPathInSimulatorRoot)

	// Read the source file
	monitorJsonData, err := os.ReadFile(sourcePathInMonitorDir) // Reading from monitor/monitor_outputs.json
	if err != nil {
		return "", fmt.Errorf("External Monitor: failed to read monitor output file %s: %w", sourcePathInMonitorDir, err)
	}

	// Write to the destination file (in simulator root)
	if err := os.WriteFile(filepath.Join("..", simulatorDestOutputFileName), monitorJsonData, 0644); err != nil {
		// We are currently in monitorDir, so dest is one level up
		return "", fmt.Errorf("External Monitor: failed to write monitor output to %s: %w", simulatorDestOutputFileName, err)
	}

	fmt.Printf("External Monitor: Finished. Output available at %s\n", simulatorDestOutputFileName)
	return simulatorDestOutputFileName, nil // Return path relative to simulator root
}

// runAIEngine executa o script Python do AI-Engine usando arquivos temporários para input e configuração,
// para evitar modificar o submódulo ai-engine.
func runAIEngine(monitorStaticFile string) (string, error) {
	fmt.Printf("AI-Engine: Iniciando. Input estático do monitor: %s\n", monitorStaticFile)

	// aiEngineDir is where main.py and temp files will be, e.g. "ai-engine/engine"
	// aiEngineDirParent is where the Makefile is, e.g. "ai-engine"
	aiEngineDirParent := "ai-engine"
	aiEngineDir := filepath.Join(aiEngineDirParent, "engine")

	// Nomes para os arquivos temporários que serão criados dentro de aiEngineDir
	tempWorkloadsJsonFile := "temp_ai_input_workloads.json"
	tempRuntimeConfigFile := "temp_ai_runtime_config.yaml"
	// Caminho relativo (ao simulador) para o output esperado do AI-Engine
	recommendationsFileRel := "ai-engine/actuator/recommendations.csv"

	// --- 1. Preparar o JSON de entrada para o AI-Engine ---
	absMonitorStaticFile, err := filepath.Abs(monitorStaticFile)
	if err != nil {
		return "", fmt.Errorf("AI-Engine: Falha ao obter caminho absoluto para %s: %v", monitorStaticFile, err)
	}

	fmt.Printf("AI-Engine: Lendo arquivo de monitor estático: %s\n", absMonitorStaticFile)
	monitorDataBytes, err := os.ReadFile(absMonitorStaticFile)
	if err != nil {
		return "", fmt.Errorf("AI-Engine: Falha ao ler arquivo de monitor estático %s: %v", absMonitorStaticFile, err)
	}

	var parsedMonitorData map[string]interface{}
	if err := json.Unmarshal(monitorDataBytes, &parsedMonitorData); err != nil {
		return "", fmt.Errorf("AI-Engine: Falha ao parsear JSON do monitor estático %s: %v", absMonitorStaticFile, err)
	}

	var workloadsList []interface{}
	if len(parsedMonitorData) > 0 {
		var firstTimestampKey string
		for k := range parsedMonitorData {
			firstTimestampKey = k
			break
		}
		if firstTimestampKey == "" {
			return "", fmt.Errorf("AI-Engine: Não foi possível obter um timestamp do JSON do monitor, embora não esteja vazio")
		}

		if tsData, ok := parsedMonitorData[firstTimestampKey].(map[string]interface{}); ok {
			if workloads, ok := tsData["workloads"].([]interface{}); ok {
				workloadsList = workloads
				fmt.Printf("AI-Engine: Extraídos %d workloads do timestamp '%s' do arquivo de monitor.\n", len(workloadsList), firstTimestampKey)
			} else {
				return "", fmt.Errorf("AI-Engine: Chave 'workloads' não é uma lista no timestamp '%s' do JSON do monitor", firstTimestampKey)
			}
		} else {
			return "", fmt.Errorf("AI-Engine: Conteúdo para o timestamp '%s' não é um objeto no JSON do monitor", firstTimestampKey)
		}
	} else {
		return "", fmt.Errorf("AI-Engine: JSON do monitor estático está vazio ou não é um objeto de timestamps")
	}

	if len(workloadsList) == 0 {
		return "", fmt.Errorf("AI-Engine: Nenhuma workload encontrada no primeiro timestamp do arquivo de monitor")
	}

	workloadsJsonBytes, err := json.MarshalIndent(workloadsList, "", "  ")
	if err != nil {
		return "", fmt.Errorf("AI-Engine: Falha ao serializar lista de workloads para JSON: %v", err)
	}

	// Caminho absoluto para o arquivo JSON temporário de workloads
	absTempWorkloadsJsonFile := filepath.Join(aiEngineDir, tempWorkloadsJsonFile)
	fmt.Printf("AI-Engine: Escrevendo JSON de workloads processado para: %s\n", absTempWorkloadsJsonFile)
	if err := os.WriteFile(absTempWorkloadsJsonFile, workloadsJsonBytes, 0644); err != nil {
		return "", fmt.Errorf("AI-Engine: Falha ao escrever JSON de workloads temporário %s: %v", absTempWorkloadsJsonFile, err)
	}
	// Defer para limpar o JSON temporário de workloads
	defer func() {
		fmt.Printf("AI-Engine: Removendo arquivo JSON de workloads temporário: %s\n", absTempWorkloadsJsonFile)
		os.Remove(absTempWorkloadsJsonFile)
	}()

	// --- 2. Preparar o arquivo de configuração YAML temporário para o AI-Engine ---
	// O input_json no YAML deve ser relativo ao diretório aiEngineDir, ou absoluto.
	// Usar o nome do arquivo relativo é mais simples se o CWD do script for aiEngineDir.
	yamlContent := fmt.Sprintf("data:\n  input_json: \"%s\"\n", tempWorkloadsJsonFile)
	absTempRuntimeConfigFile := filepath.Join(aiEngineDir, tempRuntimeConfigFile)
	fmt.Printf("AI-Engine: Escrevendo YAML de configuração temporário para: %s\n", absTempRuntimeConfigFile)
	if err := os.WriteFile(absTempRuntimeConfigFile, []byte(yamlContent), 0644); err != nil {
		return "", fmt.Errorf("AI-Engine: Falha ao escrever YAML de configuração temporário %s: %v", absTempRuntimeConfigFile, err)
	}
	// Defer para limpar o YAML de configuração temporário
	defer func() {
		fmt.Printf("AI-Engine: Removendo arquivo YAML de configuração temporário: %s\n", absTempRuntimeConfigFile)
		os.Remove(absTempRuntimeConfigFile)
	}()

	// --- 3. Executar o script Python do AI-Engine via Makefile ---
	// O tempRuntimeConfigFile (e.g., temp_ai_runtime_config.yaml) é criado em aiEngineDir (ai-engine/engine).
	// O Makefile's run-with-config target cd's para aiEngineDir antes de executar python.
	// Então, o CONFIG_FILE para make deve ser o nome base do arquivo.
	makeTarget := "run-with-config"
	makeConfigFileVar := "CONFIG_FILE=" + tempRuntimeConfigFile // tempRuntimeConfigFile is just the filename

	fmt.Printf("AI-Engine: Executando via Makefile: make %s %s (CWD: %s)\n", makeTarget, makeConfigFileVar, aiEngineDirParent)
	cmd := exec.Command("make", makeTarget, makeConfigFileVar)
	cmd.Dir = aiEngineDirParent // Run make from "ai-engine/"

	cmdOutput, err := cmd.CombinedOutput()
	if err != nil {
		return "", fmt.Errorf("AI-Engine: Falha ao executar Makefile target '%s' com config (%s): %v. Output:\n%s",
			makeTarget, tempRuntimeConfigFile, err, string(cmdOutput))
	}
	fmt.Printf("AI-Engine: Makefile target executado. Output:\n%s\n", string(cmdOutput))

	// --- 4. Verificar output e retornar caminho ---
	absRecommendationsFile, err := filepath.Abs(recommendationsFileRel)
	if err != nil {
		return "", fmt.Errorf("AI-Engine: Erro ao obter caminho absoluto para %s: %v", recommendationsFileRel, err)
	}

	if _, err := os.Stat(absRecommendationsFile); os.IsNotExist(err) {
		return "", fmt.Errorf("AI-Engine: Arquivo de recomendações esperado (%s) não foi encontrado após execução", absRecommendationsFile)
	}

	fmt.Printf("AI-Engine: Finalizado. Recomendações esperadas em %s\n", absRecommendationsFile)
	return absRecommendationsFile, nil
}

// runActuator executa o programa Go do Actuator.
// recommendationsCsvFile é o caminho absoluto para o arquivo de recomendações, usado para verificação.
func runActuator(recommendationsCsvFile string) error {
	fmt.Printf("Actuator: Iniciando. Verificando input: %s\n", recommendationsCsvFile)

	// Diretório onde o main.go do Actuator está e onde recommendations.csv deve estar.
	actuatorDir := "actuator"
	// O programa Go do Actuator lê "recommendations.csv" diretamente do seu CWD.
	// actuatorScript := "main.go" // Não é um script, é um programa Go

	// Verificar se o recommendationsCsvFile (que o AI-Engine deveria ter criado) existe
	if _, err := os.Stat(recommendationsCsvFile); os.IsNotExist(err) {
		log.Printf("Actuator: Arquivo de recomendações %s não encontrado (esperado ser criado pelo AI-Engine).", recommendationsCsvFile)
		return fmt.Errorf("actuator: arquivo de recomendações %s não encontrado", recommendationsCsvFile)
	}
	fmt.Printf("Actuator: Arquivo de recomendações %s encontrado.\n", recommendationsCsvFile)

	fmt.Printf("Actuator: Executando programa Go: go run main.go --csv %s no diretório %s\n", recommendationsCsvFile, actuatorDir)

	cmd := exec.Command("go", "run", "main.go", "--csv", recommendationsCsvFile)
	cmd.Dir = actuatorDir // Define o diretório de trabalho para actuator/
	// KUBECONFIG setting is now handled within actuator/orchestrators/karmada.go
	// homeDir, err := os.UserHomeDir()
	// if err != nil {
	// 	return fmt.Errorf("actuator: failed to get user home directory: %w", err)
	// }
	// karmadaKubeconfigPath := filepath.Join(homeDir, ".kube", "karmada.config")
	// cmd.Env = append(os.Environ(), "KUBECONFIG="+karmadaKubeconfigPath)
	// log.Printf("Actuator: Setting KUBECONFIG for Actuator to: %s", karmadaKubeconfigPath)

	cmdOutput, err := cmd.CombinedOutput()
	if err != nil {
		log.Printf("Actuator: Falha ao executar programa Go (go run main.go em %s): %v", actuatorDir, err)
		log.Printf("Actuator: Output do programa Go:\n%s", string(cmdOutput))
		return fmt.Errorf("actuator: falha ao executar programa Go: %w. Output: %s", err, string(cmdOutput))
	}

	fmt.Printf("Actuator: Programa Go executado com sucesso. Output:\n%s", string(cmdOutput))
	fmt.Println("Actuator: Finalizou a aplicação das recomendações.")
	return nil
}

func main() {
	fmt.Println("Simulador iniciando o ciclo de operações...")

	csv_path := "data/recorte_5min.csv"
	yaml_path := "data/config.yaml"

	config_yaml, err := os.Open(yaml_path)
	if err != nil {
		log.Fatalf("Falha ao abrir configuração YAML %s: %v", yaml_path, err)
	}
	// defer config_yaml.Close() // Fecharemos explicitamente após o uso pelo Broker

	csv_data, err := os.Open(csv_path)
	if err != nil {
		log.Fatalf("Falha ao abrir dados CSV %s: %v", csv_path, err)
	}
	// defer csv_data.Close() // Fecharemos explicitamente após o uso pelo Broker

	// Etapa 1: Broker
	fmt.Println("\n--- Iniciando Broker ---")
	broker.Run(csv_data, config_yaml) // Passando os leitores originais
	csv_data.Close()                  // Fechando após o uso pelo broker
	config_yaml.Close()               // Fechando após o uso pelo broker
	fmt.Println("--- Broker finalizou ---")

	// Etapa 2: Monitor
	fmt.Println("\n--- Iniciando Monitor Externo ---")
	// Run the external monitor for 10 seconds (adjust as needed)
	monitorOutputFile, err := runExternalMonitorAndFetchOutput(10 * time.Second)
	if err != nil {
		log.Fatalf("Monitor Externo falhou: %v. Encerrando simulador.", err)
	}
	fmt.Printf("--- Output do Monitor Externo em: %s ---\n", monitorOutputFile)

	// Etapa 3: AI-Engine
	// O AI-Engine utilizará o monitor_output.json (gerado)
	fmt.Println("\n--- Iniciando AI-Engine ---")
	recommendationsCsvFile, err := runAIEngine(monitorOutputFile)
	if err != nil {
		log.Fatalf("AI-Engine falhou: %v. Encerrando simulador.", err)
	}
	fmt.Printf("--- AI-Engine finalizou, recomendações em: %s ---\n", recommendationsCsvFile)

	// Etapa 4: Actuator
	// O Actuator utilizará o recommendations.csv gerado pelo AI-Engine.
	fmt.Println("\n--- Iniciando Actuator ---")
	err = runActuator(recommendationsCsvFile)
	if err != nil {
		log.Fatalf("Actuator falhou: %v. Encerrando simulador.", err)
	}
	fmt.Println("--- Actuator finalizou ---")

	fmt.Println("\nSimulador completou todas as etapas com sucesso!")
}
