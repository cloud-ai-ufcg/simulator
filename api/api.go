package api

import (
	"bytes"
	"encoding/csv"
	"encoding/json"
	"fmt"
	"io"
	"io/ioutil"
	"net/http"
	"os"
	"strconv"
	"time"
)

// CallBrokerAPI envia uma requisição POST para a API do Broker.
func CallBrokerAPI(inputFilePath string, apiURL string) error {
	fmt.Printf("Chamando API do Broker em %s com o arquivo %s...\n", apiURL, inputFilePath)

	// Ler o arquivo JSON de entrada
	inputData, err := ioutil.ReadFile(inputFilePath)
	if err != nil {
		return fmt.Errorf("erro ao ler arquivo de entrada %s: %w", inputFilePath, err)
	}

	// Criar a requisição HTTP
	req, err := http.NewRequest("POST", apiURL, bytes.NewBuffer(inputData))
	if err != nil {
		return fmt.Errorf("erro ao criar requisição HTTP: %w", err)
	}

	// Configurar os headers
	req.Header.Set("Content-Type", "application/json")

	// Enviar a requisição
	client := &http.Client{Timeout: 30 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return fmt.Errorf("erro ao enviar requisição para API do Broker: %w", err)
	}
	defer resp.Body.Close()

	// Verificar o status da resposta
	if resp.StatusCode != http.StatusOK {
		body, _ := ioutil.ReadAll(resp.Body)
		return fmt.Errorf("API retornou status %d: %s", resp.StatusCode, string(body))
	}

	fmt.Println("Broker API chamada com sucesso.")
	return nil
}

// ActuatorRecommendation representa uma recomendação para ser enviada à API do Actuator
type ActuatorRecommendation struct {
	WorkloadID string `json:"workload_id"` // string
	Label      int    `json:"label"`       // int
	Kind       string `json:"kind"`        // string
}

// ConvertCSVToJSON lê um arquivo CSV de recomendações e retorna um JSON pronto para envio
func ConvertCSVToJSON(csvFilePath string) ([]byte, error) {
	// Abrir arquivo CSV
	file, err := os.Open(csvFilePath)
	if err != nil {
		return nil, fmt.Errorf("erro ao abrir arquivo de recomendações: %w", err)
	}
	defer file.Close()

	reader := csv.NewReader(file)

	// Ler cabeçalho e mapear índices das colunas
	header, err := reader.Read()
	if err != nil {
		return nil, fmt.Errorf("erro ao ler cabeçalho do CSV: %w", err)
	}
	colIdx := map[string]int{}
	for i, col := range header {
		colIdx[col] = i
	}
	required := []string{"workload_id", "label", "kind"}
	for _, col := range required {
		if _, ok := colIdx[col]; !ok {
			return nil, fmt.Errorf("coluna obrigatória '%s' não encontrada no cabeçalho do CSV", col)
		}
	}

	var recommendations []ActuatorRecommendation

	// Ler registros
	for {
		record, err := reader.Read()
		if err == io.EOF {
			break
		}
		if err != nil {
			return nil, fmt.Errorf("erro ao ler registro do CSV: %w", err)
		}

		// Verificar se há colunas suficientes
		if len(record) < len(header) {
			return nil, fmt.Errorf("registro CSV inválido: esperado pelo menos %d colunas, obtido %d", len(header), len(record))
		}

		// Obter valores pelas posições dinâmicas
		workloadID := record[colIdx["workload_id"]]
		labelStr := record[colIdx["label"]]
		kind := record[colIdx["kind"]]

		// Converter label para inteiro
		label, err := strconv.Atoi(labelStr)
		if err != nil {
			return nil, fmt.Errorf("erro ao converter label '%s' para inteiro na linha: %w", labelStr, err)
		}

		// Adicionar namespace ao workload_id se não estiver presente
		if len(workloadID) > 0 && !containsSlash(workloadID) {
			workloadID = "default/" + workloadID
		}

		recommendations = append(recommendations, ActuatorRecommendation{
			WorkloadID: workloadID,
			Label:      label,
			Kind:       kind,
		})
	}

	// Converter para JSON
	jsonData, err := json.Marshal(recommendations)
	if err != nil {
		return nil, fmt.Errorf("erro ao converter para JSON: %w", err)
	}

	return jsonData, nil
}

// CallActuatorAPI lê o arquivo CSV de recomendações e envia para o endpoint /apply do Actuator API
func CallActuatorAPI(recommendationsFilePath string, apiURL string) error {
	fmt.Printf("Chamando API do Actuator em %s com o arquivo %s...\n", apiURL, recommendationsFilePath)

	// Converter CSV para JSON
	jsonData, err := ConvertCSVToJSON(recommendationsFilePath)
	if err != nil {
		return fmt.Errorf("erro ao converter CSV para JSON: %w", err)
	}

	// Criar requisição POST
	req, err := http.NewRequest("POST", apiURL+"apply", bytes.NewBuffer(jsonData))
	if err != nil {
		return fmt.Errorf("erro ao criar requisição HTTP: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")

	// Enviar requisição
	client := &http.Client{Timeout: 30 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return fmt.Errorf("erro ao enviar requisição: %w", err)
	}
	defer resp.Body.Close()

	// Ler resposta
	body, err := ioutil.ReadAll(resp.Body)
	if err != nil {
		return fmt.Errorf("erro ao ler resposta: %w", err)
	}

	// Verificar status da resposta
	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("API retornou erro %d: %s", resp.StatusCode, string(body))
	}

	fmt.Printf("Actuator API chamada com sucesso. Resposta: %s\n", string(body))
	return nil
}

// Função auxiliar para verificar se a string contém uma barra (/)
func containsSlash(s string) bool {
	for _, c := range s {
		if c == '/' {
			return true
		}
	}
	return false
}
