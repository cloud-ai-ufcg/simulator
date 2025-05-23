#!/bin/bash

set -e

echo "Atualizando pacotes e instalando curl..."
sudo apt update

if ! command -v curl >/dev/null 2>&1; then
  sudo apt install -y curl
else
  echo "curl já está instalado"
fi

echo "Verificando e instalando Docker..."

if ! command -v docker >/dev/null 2>&1; then
  sudo apt install -y ca-certificates gnupg lsb-release
  sudo install -m 0755 -d /etc/apt/keyrings

  if [ ! -f /etc/apt/keyrings/docker.gpg ]; then
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
      sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  fi

  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
    https://download.docker.com/linux/ubuntu \
    $(lsb_release -cs) stable" | \
    sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

  sudo apt update
  sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

  sudo usermod -aG docker $USER
  newgrp docker
else
  echo "Docker já está instalado"
fi

echo "Verificando e instalando make..."
if ! command -v make >/dev/null 2>&1; then
  sudo apt install -y make
else
  echo "make já está instalado"
fi

echo "Verificando e instalando Golang..."
if ! command -v go >/dev/null 2>&1; then
  GO_VERSION="1.24.2"
  ARCH=$(dpkg --print-architecture)
  wget https://go.dev/dl/go${GO_VERSION}.linux-${ARCH}.tar.gz
  sudo rm -rf /usr/local/go
  sudo tar -C /usr/local -xzf go${GO_VERSION}.linux-${ARCH}.tar.gz
  rm go${GO_VERSION}.linux-${ARCH}.tar.gz

  if ! grep -q "/usr/local/go/bin" <<< "$PATH"; then
    echo "export PATH=\$PATH:/usr/local/go/bin" >> ~/.bashrc
    export PATH=$PATH:/usr/local/go/bin
  fi

  echo "Go ${GO_VERSION} instalado com sucesso"
else
  echo "Golang já está instalado: $(go version)"
fi

echo "Ajustando limites do inotify..."
sudo sysctl fs.inotify.max_user_watches=524288
sudo sysctl fs.inotify.max_user_instances=512

if ! grep -q "fs.inotify.max_user_watches=524288" /etc/sysctl.conf; then
  echo "fs.inotify.max_user_watches=524288" | sudo tee -a /etc/sysctl.conf
fi

if ! grep -q "fs.inotify.max_user_instances=512" /etc/sysctl.conf; then
  echo "fs.inotify.max_user_instances=512" | sudo tee -a /etc/sysctl.conf
fi
sudo sysctl -p


echo "Verificando e instalando Git..."
if ! command -v git >/dev/null 2>&1; then
  sudo apt install -y git
else
  echo "Git já está instalado"
fi

echo "Verificando e instalando kubectl..."
if ! command -v kubectl >/dev/null 2>&1; then
  curl -LO "https://dl.k8s.io/release/$(curl -sL https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
  chmod +x kubectl
  sudo mv kubectl /usr/local/bin/
else
  echo "kubectl já está instalado"
fi

echo "Verificando e instalando Helm..."
if ! command -v helm >/dev/null 2>&1; then
  curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
else
  echo "Helm já está instalado"
fi

echo "Verificando e instalando kind..."
if ! command -v kind >/dev/null 2>&1; then
  curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.22.0/kind-linux-amd64
  chmod +x ./kind
  sudo mv ./kind /usr/local/bin/kind
else
  echo "kind já está instalado"
fi

echo "Verificando se o repositório do autoscaler já foi clonado..."
if [ ! -d "autoscaler" ]; then
  git clone https://github.com/kubernetes/autoscaler.git
else
  echo "Repositório autoscaler já existe"
fi

echo "Verificando se o repositório do karmada já foi clonado..."
if [ ! -d "karmada" ]; then
  git clone https://github.com/karmada-io/karmada.git
else
  echo "Repositório karmada já existe"
fi

echo "Instalação concluída com sucesso!"
