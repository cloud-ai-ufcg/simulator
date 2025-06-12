package utils

import (
	"fmt" // Mantenha se usado por outras funções, senão remova
	"os"
	"path/filepath"
	"time"
)

// Função para aguardar um arquivo aparecer
func WaitForFile(path string, timeout time.Duration) error {
	fmt.Printf("Aguardando arquivo %s aparecer...\n", path)

	start := time.Now()
	for {
		if _, err := os.Stat(path); err == nil {
			fmt.Printf("Arquivo detectado: %s após %v.\n", path, time.Since(start))
			return nil
		}

		if timeout > 0 && time.Since(start) > timeout {
			return fmt.Errorf("tempo limite ao esperar pelo arquivo: %s", path)
		}

		time.Sleep(500 * time.Millisecond)
	}
}

// Função para limpar um diretório
func ClearOutputDir(path string) error {
	fmt.Printf("Limpando diretório de saída: %s...\n", path)

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
	fmt.Printf("Diretório %s limpo com sucesso.\n", path)
	return nil
}
