#!/bin/bash
set -euo pipefail

# Color (Magenta for this script)
COLOR="\033[1;35m"
RESET="\033[0m"

echo -e "${COLOR}🔧 Checking prerequisites...${RESET}"

function install_curl() {
  if ! command -v curl &> /dev/null; then
    echo -e "${COLOR}📦 Installing curl...${RESET}"
    sudo apt update
    sudo apt install -y curl
  else
    echo -e "${COLOR}✅ curl is already installed.${RESET}"
  fi
}

function install_docker() {
  if ! command -v docker &> /dev/null; then
    echo -e "${COLOR}🐳 Installing Docker...${RESET}"
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

    echo -e "${COLOR}ℹ️ Docker installed and user added to 'docker' group.${RESET}"

    read -p "❓ Do you want to start a new shell with 'docker' group now? [y/N] " answer
    if [[ "$answer" =~ ^[yY]$ ]]; then
      echo -e "${COLOR}🔁 Starting new shell with docker group. Type 'exit' to return to the previous shell.${RESET}"
      newgrp docker
    else
      echo -e "${COLOR}ℹ️ You can run 'newgrp docker' manually later or restart your session.${RESET}"
    fi
  else
    echo -e "${COLOR}✅ Docker is already installed.${RESET}"
  fi
}

function install_git() {
  if ! command -v git &> /dev/null; then
    echo -e "${COLOR}🐙 Installing Git...${RESET}"
    sudo apt install -y git
  else
    echo -e "${COLOR}✅ Git is already installed.${RESET}"
  fi
}

function install_kubectl() {
  if ! command -v kubectl &> /dev/null; then
    echo -e "${COLOR}📦 Installing kubectl...${RESET}"
    curl -LO "https://dl.k8s.io/release/$(curl -sL https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
    chmod +x kubectl
    sudo mv kubectl /usr/local/bin/
  else
    echo -e "${COLOR}✅ kubectl is already installed.${RESET}"
  fi
}

function install_helm() {
  if ! command -v helm &> /dev/null; then
    echo -e "${COLOR}⛵ Installing Helm...${RESET}"
    curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
  else
    echo -e "${COLOR}✅ Helm is already installed.${RESET}"
  fi
}

function install_kind() {
  if ! command -v kind &> /dev/null; then
    echo -e "${COLOR}🧱 Installing kind...${RESET}"
    curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.29.0/kind-linux-amd64
    chmod +x ./kind
    sudo mv ./kind /usr/local/bin/kind
  else
    echo -e "${COLOR}✅ kind is already installed.${RESET}"
  fi
}

function install_jq() {
  if ! command -v jq &> /dev/null; then
    echo -e "${COLOR}🔧 Installing jq...${RESET}"
    sudo apt install -y jq
  else
    echo -e "${COLOR}✅ jq is already installed.${RESET}"
  fi
}

function install_make() {
  if ! command -v make &> /dev/null; then
    echo -e "${COLOR}📐 Installing make...${RESET}"
    sudo apt install -y make
  else
    echo -e "${COLOR}✅ make is already installed.${RESET}"
  fi
}

function install_python3() {
  if ! command -v python3 &> /dev/null; then
    echo -e "${COLOR}🐍 Installing Python 3...${RESET}"
    sudo apt install -y python3
  else
    echo -e "${COLOR}✅ Python 3 is already installed.${RESET}"
  fi
}

function install_pip() {
  if ! command -v pip &> /dev/null; then
    echo -e "${COLOR}🐍 Installing pip...${RESET}"
    sudo apt install -y python3-pip
  else
    echo -e "${COLOR}✅ pip is already installed.${RESET}"
  fi
}

function install_go() {
  if ! command -v go &> /dev/null; then
    echo -e "${COLOR}🔧 Installing Golang...${RESET}"
    GO_VERSION="1.21.0"
    curl -LO https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz
    sudo rm -rf /usr/local/go
    sudo tar -C /usr/local -xzf go${GO_VERSION}.linux-amd64.tar.gz
    rm "go${GO_VERSION}.linux-amd64.tar.gz"
    echo 'export PATH=$PATH:/usr/local/go/bin' >> ~/.bashrc
    export PATH=$PATH:/usr/local/go/bin
    echo -e "${COLOR}ℹ️ Golang installed. PATH has been updated.${RESET}"

    read -p "❓ Do you want to run 'source ~/.bashrc' now to apply the changes? [y/N] " answer
    if [[ "$answer" =~ ^[yY]$ ]]; then
      source ~/.bashrc
      echo -e "${COLOR}✅ PATH updated successfully.${RESET}"
    else
      echo -e "${COLOR}ℹ️ You can run 'source ~/.bashrc' manually later or open a new terminal.${RESET}"
    fi
  else
    echo -e "${COLOR}✅ Golang is already installed.${RESET}"
  fi
}

# Run all checks
install_curl
install_docker
install_git
install_kubectl
install_helm
install_kind
install_jq
install_make
install_python3
install_pip
install_go

echo -e "${COLOR}✅ Environment is ready.${RESET}"
