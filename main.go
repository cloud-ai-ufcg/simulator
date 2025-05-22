package main

import (
	"encoding/json"
	"fmt"
	"log"
	"os"
	"os/exec"
	"path/filepath"
	"time"

	"github.com/cloud-ai-ufcg/broker/broker"
)

// MonitorDataEntry representa uma entrada de dados do monitor
type MonitorDataEntry struct {
	Timestamp string `json:"timestamp"`
	Message   string `json:"message"`
}

// monitor coleta métricas por um período definido e salva em um arquivo JSON.
// Retorna o caminho do arquivo de output e um erro, se houver.
func monitor() (string, error) {
	fmt.Println("Monitor iniciando...")
	outputFilePath := "monitor_output.json" // Nome do arquivo de saída conforme solicitado
	var metricsLog []MonitorDataEntry

	totalDuration := 30 * time.Second
	interval := 3 * time.Second
	iterations := int(totalDuration / interval)

	fmt.Printf("Monitor coletando métricas por %v (intervalo de %v)...\n", totalDuration, interval)
	for i := 0; i < iterations; i++ {
		entry := MonitorDataEntry{
			Timestamp: time.Now().Format(time.RFC3339),
			Message:   fmt.Sprintf("Coleta de métricas #%d", i+1),
		}
		metricsLog = append(metricsLog, entry)
		// Log no console para acompanhamento
		fmt.Printf("Monitor: %s - %s\n", entry.Timestamp, entry.Message)
		time.Sleep(interval)
	}

	jsonData, err := json.MarshalIndent(metricsLog, "", "  ")
	if err != nil {
		log.Printf("Falha ao gerar JSON dos dados do monitor: %v", err)
		return "", err
	}

	err = os.WriteFile(outputFilePath, jsonData, 0644)
	if err != nil {
		log.Printf("Falha ao escrever output do monitor para %s: %v", outputFilePath, err)
		return "", err
	}

	fmt.Printf("Monitor finalizado. Output escrito em %s\n", outputFilePath)
	return outputFilePath, nil
}

// runAIEngine executa o script Python do AI-Engine usando arquivos temporários para input e configuração,
// para evitar modificar o submódulo ai-engine.
func runAIEngine(monitorStaticFile string) (string, error) {
	fmt.Printf("AI-Engine: Iniciando. Input estático do monitor: %s\n", monitorStaticFile)

	aiEngineDir := "ai-engine/engine"
	aiEngineScript := "main.py"
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

	// --- 3. Executar o script Python do AI-Engine ---
	// Assumimos que o main.py original do submódulo aceita --config <nome_do_arquivo_yaml>
	fmt.Printf("AI-Engine: Executando script: python %s --config %s (CWD: %s)\n", aiEngineScript, tempRuntimeConfigFile, aiEngineDir)
	cmd := exec.Command("python", aiEngineScript, "--config", tempRuntimeConfigFile)
	cmd.Dir = aiEngineDir

	cmdOutput, err := cmd.CombinedOutput()
	if err != nil {
		return "", fmt.Errorf("AI-Engine: Falha ao executar script Python (%s) com config (%s): %v. Output:\n%s",
			aiEngineScript, tempRuntimeConfigFile, err, string(cmdOutput))
	}
	fmt.Printf("AI-Engine: Script Python executado. Output:\n%s\n", string(cmdOutput))

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
	actuatorDir := "ai-engine/actuator"
	// O programa Go do Actuator lê "recommendations.csv" diretamente do seu CWD.
	// actuatorScript := "main.go" // Não é um script, é um programa Go

	// Verificar se o recommendationsCsvFile (que o AI-Engine deveria ter criado) existe
	if _, err := os.Stat(recommendationsCsvFile); os.IsNotExist(err) {
		log.Printf("Actuator: Arquivo de recomendações %s não encontrado (esperado ser criado pelo AI-Engine).", recommendationsCsvFile)
		return fmt.Errorf("actuator: arquivo de recomendações %s não encontrado", recommendationsCsvFile)
	}
	fmt.Printf("Actuator: Arquivo de recomendações %s encontrado.\n", recommendationsCsvFile)

	fmt.Printf("Actuator: Executando programa Go: go run main.go no diretório %s\n", actuatorDir)

	cmd := exec.Command("go", "run", "main.go")
	cmd.Dir = actuatorDir // Define o diretório de trabalho para ai-engine/actuator/

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

	// Etapa 2: Monitor (Usando arquivo de exemplo estático)
	fmt.Println("\n--- Usando output estático do Monitor --- ")
	monitorOutputFile := "monitor_outputs.json" // Caminho para o arquivo de exemplo
	// Verificar se o arquivo de exemplo do monitor existe
	if _, err := os.Stat(monitorOutputFile); os.IsNotExist(err) {
		log.Fatalf("Arquivo de output do monitor de exemplo '%s' não encontrado. Certifique-se de que ele existe na raiz do projeto.", monitorOutputFile)
	}
	// // Chamada original para a função monitor, agora comentada:
	// fmt.Println("\n--- Iniciando Monitor ---")
	// monitorOutputFile, err := monitor()
	// if err != nil {
	// 	log.Fatalf("Monitor falhou: %v. Encerrando simulador.", err)
	// }
	fmt.Printf("--- Usando output do Monitor de: %s ---\n", monitorOutputFile)

	// Etapa 3: AI-Engine
	// O AI-Engine utilizará o monitor_output.json (estático ou gerado)
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
