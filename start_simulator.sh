#!/bin/bash
set -e

# Detecta se está rodando no WSL
if grep -qEi "(Microsoft|WSL)" /proc/version &> /dev/null ; then
    echo "Ambiente detectado: WSL"
    
    # Obter usuário Windows via comando do Windows
    WIN_USER=$(cmd.exe /c "echo %USERNAME%" 2>/dev/null | tr -d '\r')
    
    if [ -z "$WIN_USER" ]; then
        echo "Não foi possível detectar o usuário Windows, usando valor padrão 'yalle'"
        WIN_USER="yalle"
    fi

    export HOME="/mnt/c/Users/$WIN_USER"
else
    echo "Ambiente detectado: Linux normal"
    export HOME="$HOME"
fi

echo "HOME environment variable set to: $HOME"

echo -e "\e[32mConfigurando dependências do AI-Engine...\e[0m"
python3 -m pip install -r ai-engine/requirements.txt
echo -e "\e[32mDependências do AI-Engine configuradas com sucesso.\e[0m"

echo -e "\e[36mIniciando o Simulador Go...\e[0m"
go run main.go

echo -e "\e[36mSimulador Go finalizado.\e[0m"
echo -e "\e[32mProcesso de inicialização completo.\e[0m"