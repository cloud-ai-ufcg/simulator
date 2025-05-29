#!/bin/bash
set -euo pipefail

chmod +x install_prerequisites.sh generate_manifests.sh create_kind_cluster.sh install_prometheus.sh ASsetup.sh

echo "[1/5] Instalando pré-requisitos..."
./install_prerequisites.sh

echo "[2/5] Gerando manifests..."
./generate_manifests.sh

echo "[3/5] Criando cluster KIND..."
./create_kind_cluster.sh

# Aguarda o cluster KIND responder ao kubectl
echo "[⏳] Aguardando o cluster KIND estar pronto..."
for i in {1..30}; do
  if kubectl get nodes &> /dev/null; then
    echo "[✅] Cluster responde ao kubectl."
    break
  fi
  echo "[...] Tentativa $i: aguardando cluster estar acessível (3s)..."
  sleep 3
done

# Verifica se o nó control-plane está Ready
echo "[⏳] Verificando se o nó control-plane está pronto..."
for i in {1..20}; do
  if kubectl get nodes | grep "control-plane" | grep -q " Ready"; then
    echo "[✅] Nó control-plane está pronto."
    break
  fi
  echo "[...] Aguardando nó control-plane estar Ready (3s)..."
  sleep 3
done

echo "[4/5] Instalando Prometheus..."
./install_prometheus.sh

# Espera pelo pod do Prometheus Server estar Running e Ready
echo "[⏳] Verificando se Prometheus está rodando..."
for i in {1..30}; do
  STATUS=$(kubectl get pod -n monitoring -l app.kubernetes.io/name=prometheus,app.kubernetes.io/component=server \
    -o jsonpath="{.items[0].status.phase}" 2>/dev/null || echo "NotFound")
  READY=$(kubectl get pod -n monitoring -l app.kubernetes.io/name=prometheus,app.kubernetes.io/component=server \
    -o jsonpath="{.items[0].status.containerStatuses[0].ready}" 2>/dev/null || echo "false")
  if [[ "$STATUS" == "Running" && "$READY" == "true" ]]; then
    echo "[✅] Prometheus está rodando."
    break
  fi
  echo "[...] Tentativa $i: aguardando Prometheus estar pronto (3s)..."
  sleep 3
done

echo "[5/5] Aplicando setup do autoscaler..."
./ASsetup.sh

echo "[🎉] Ambiente completo criado com sucesso!"
