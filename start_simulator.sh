#!/bin/bash

# A variável de ambiente HOME geralmente já está definida corretamente em ambientes Unix-like.
# Esta linha é mais para garantir ou para casos onde ela possa não estar.
export HOME="${HOME:-$USERPROFILE}" # Usa HOME se definida, senão tenta USERPROFILE (para WSL/Git Bash)

# Exibe uma mensagem informando o valor de HOME (opcional, para feedback)
echo "Variável de ambiente HOME está definida como: $HOME"

# Executa o programa Go principal do simulador
echo "Iniciando o simulador..."
go run main.go 