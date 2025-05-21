#!/bin/bash

# Garante que HOME esteja definida, usando USERPROFILE como fallback (útil para WSL/Git Bash).
export HOME="${HOME:-$USERPROFILE}"

echo "Variável de ambiente HOME está definida como: $HOME"

echo "Iniciando o simulador..."
go run main.go 