package api

import (
	"bytes"
	"fmt"
	"io/ioutil"
	"net/http"
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
