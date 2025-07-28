#!/bin/bash
# Script para criar venv e instalar dependências do requirements.txt

set -e

VENV_DIR="../venv"
REQ_FILE="../avaliator/requirements.txt"

# Cria venv se não existir ou repara se estiver corrompido
if [ ! -d "$VENV_DIR" ]; then
    echo "Criando ambiente virtual..."
    python3 -m venv "$VENV_DIR"
elif [ ! -f "$VENV_DIR/bin/activate" ]; then
    echo "Reparando ambiente virtual corrompido..."
    python3 -m venv --clear "$VENV_DIR"
fi

# Verifica se o reparo foi bem-sucedido
if [ ! -f "$VENV_DIR/bin/activate" ]; then
    echo "❌ Erro: Falha ao criar/reparar ambiente virtual"
    exit 1
fi

# Ativa venv
source "$VENV_DIR/bin/activate"

# Instala dependências
pip install --upgrade pip
pip install -r "$REQ_FILE"

echo "Ambiente virtual criado e dependências instaladas."
