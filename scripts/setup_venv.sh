#!/bin/bash
# Script para criar venv e instalar dependências do requirements.txt

set -e

VENV_DIR="../venv"
REQ_FILE="../avaliator/requirements.txt"

# Cria venv se não existir
if [ ! -d "$VENV_DIR" ]; then
    python3 -m venv "$VENV_DIR"
fi

# Ativa venv
source "$VENV_DIR/bin/activate"

# Instala dependências
pip install --upgrade pip
pip install -r "$REQ_FILE"

echo "Ambiente virtual criado e dependências instaladas."
