#!/bin/bash
set -euo pipefail

# Garantir permissões de execução para todos os scripts necessários
chmod +x install_prerequisites.sh generate_manifests.sh install_karmada.sh install_prometheus.sh ASsetup.sh

echo "[1/5] 📦 Instalando pré-requisitos..."
./install_prerequisites.sh

echo "[2/5] 📝 Gerando arquivos de configuração (manifests)..."
./generate_manifests.sh

echo "[3/5] ☸️ Subindo ambiente Karmada..."
./install_karmada.sh

export KUBECONFIG=~/.kube/karmada.config

# Aguarda resposta do kubectl (em qualquer contexto atual)
echo "[⏳] Verificando acesso via kubectl..."
for i in {1..30}; do
  if kubectl version --client &> /dev/null && kubectl get nodes &> /dev/null; then
    echo "[✅] kubectl está funcional e cluster acessível."
    break
  fi
  echo "[...] Tentativa $i: aguardando cluster (3s)..."
  sleep 3
done

# Verifica se algum nó está pronto
echo "[⏳] Verificando se algum nó do cluster está Ready..."
for i in {1..20}; do
  if kubectl get nodes | grep -q " Ready"; then
    echo "[✅] Pelo menos um nó está pronto."
    break
  fi
  echo "[...] Tentativa $i: aguardando nó Ready (3s)..."
  sleep 3
done

echo "[4/5] 📊 Instalando Prometheus..."
./install_prometheus.sh

# Espera pelo pod do Prometheus Server estar rodando
echo "[⏳] Verificando se Prometheus está rodando..."
for i in {1..30}; do
  STATUS=$(kubectl get pod -n monitoring -l app.kubernetes.io/name=prometheus,app.kubernetes.io/component=server \
    -o jsonpath="{.items[0].status.phase}" 2>/dev/null || echo "NotFound")
  READY=$(kubectl get pod -n monitoring -l app.kubernetes.io/name=prometheus,app.kubernetes.io/component=server \
    -o jsonpath="{.items[0].status.containerStatuses[0].ready}" 2>/dev/null || echo "false")
  if [[ "$STATUS" == "Running" && "$READY" == "true" ]]; then
    echo "[✅] Prometheus está rodando corretamente."
    break
  fi
  echo "[...] Tentativa $i: aguardando Prometheus estar pronto (3s)..."
  sleep 3
done

echo "[5/5] ⚙️ Aplicando configuração do Cluster Autoscaler..."
./ASsetup.sh

echo ""
echo "[🎉] Ambiente Kubernetes com Karmada e Autoscaler provisionado com sucesso!"
