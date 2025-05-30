#!/bin/bash
set -euo pipefail

echo "🔧 Verificando pré-requisitos..."

function instalar_curl() {
  if ! command -v curl &> /dev/null; then
    echo "📦 Instalando curl..."
    sudo apt update
    sudo apt install -y curl
  else
    echo "✅ curl já está instalado."
  fi
}

function instalar_docker() {
  if ! command -v docker &> /dev/null; then
    echo "🐳 Instalando Docker..."
    sudo apt install -y ca-certificates gnupg lsb-release
    sudo install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
      https://download.docker.com/linux/ubuntu \
      $(lsb_release -cs) stable" | \
      sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    sudo apt update
    sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    sudo usermod -aG docker "$USER"
    echo "ℹ️ Reinicie o shell ou rode 'newgrp docker' para aplicar permissões de grupo."
  else
    echo "✅ Docker já está instalado."
  fi
}

function instalar_git() {
  if ! command -v git &> /dev/null; then
    echo "🐙 Instalando Git..."
    sudo apt install -y git
  else
    echo "✅ Git já está instalado."
  fi
}

function instalar_kubectl() {
  if ! command -v kubectl &> /dev/null; then
    echo "📦 Instalando kubectl..."
    curl -LO "https://dl.k8s.io/release/$(curl -sL https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
    chmod +x kubectl
    sudo mv kubectl /usr/local/bin/
  else
    echo "✅ kubectl já está instalado."
  fi
}

function instalar_helm() {
  if ! command -v helm &> /dev/null; then
    echo "⛵ Instalando Helm..."
    curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
  else
    echo "✅ Helm já está instalado."
  fi
}

function instalar_kind() {
  if ! command -v kind &> /dev/null; then
    echo "🧱 Instalando kind..."
    curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.29.0/kind-linux-amd64
    chmod +x ./kind
    sudo mv ./kind /usr/local/bin/kind
  else
    echo "✅ kind já está instalado."
  fi
}

function instalar_jq() {
  if ! command -v jq &> /dev/null; then
    echo "🔧 Instalando jq..."
    sudo apt install -y jq
  else
    echo "✅ jq já está instalado."
  fi
}

function instalar_make() {
  if ! command -v make &> /dev/null; then
    echo "📐 Instalando make..."
    sudo apt install -y make
  else
    echo "✅ make já está instalado."
  fi
}

function instalar_python3() {
  if ! command -v python3 &> /dev/null; then
    echo "🐍 Instalando Python 3..."
    sudo apt install -y python3
  else
    echo "✅ Python 3 já está instalado."
  fi
}

function instalar_pip() {
  if ! command -v pip &> /dev/null; then
    echo "🐍 Instalando pip..."
    sudo apt install -y python3-pip
  else
    echo "✅ pip já está instalado."
  fi
}

function instalar_go() {
  if ! command -v go &> /dev/null; then
    echo "🔧 Instalando Golang..."
    GO_VERSION="1.21.0"
    curl -LO https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz
    sudo rm -rf /usr/local/go
    sudo tar -C /usr/local -xzf go${GO_VERSION}.linux-amd64.tar.gz
    rm go${GO_VERSION}.linux-amd64.tar.gz
    echo 'export PATH=$PATH:/usr/local/go/bin' >> ~/.bashrc
    export PATH=$PATH:/usr/local/go/bin
    echo "ℹ️ Golang instalado. Reinicie o shell ou rode 'source ~/.bashrc'."
  else
    echo "✅ Golang já está instalado."
  fi
}

# Executar verificações
instalar_curl
instalar_docker
instalar_git
instalar_kubectl
instalar_helm
instalar_kind
instalar_jq
instalar_make
instalar_pip
instalar_go

echo "✅ Ambiente pronto."
