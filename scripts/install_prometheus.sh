#!/bin/bash
set -euo pipefail

RELEASE_NAME="prometheus"
NAMESPACE="monitoring"
SLEEP_TIME=${SLEEP_TIME:-5}

export KUBECONFIG=~/.kube/members.config

for CONTEXT in member1 member2; do
  echo "⛵ [$CONTEXT] Instalando Prometheus..."

  kubectl config use-context "$CONTEXT"

  echo "🔧 Criando namespace '$NAMESPACE' (se necessário)..."
  kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

  echo "📦 Configurando Helm..."
  helm repo add prometheus-community https://prometheus-community.github.io/helm-charts || true
  helm repo update

  echo "🧹 Removendo release antiga (se houver)..."
  helm uninstall "$RELEASE_NAME" -n "$NAMESPACE" || true

  echo "🚀 Instalando Prometheus via Helm no contexto $CONTEXT..."
  helm upgrade --install "$RELEASE_NAME" prometheus-community/prometheus \
    --namespace "$NAMESPACE" \
    --wait \
    --set alertmanager.enabled=false \
    --set pushgateway.enabled=false \
    --set server.persistentVolume.enabled=false \
    --set server.service.type=ClusterIP

  echo "⏳ Aguardando Prometheus rodar no cluster $CONTEXT..."
  for i in {1..40}; do
    POD_NAME=$(kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=prometheus,app.kubernetes.io/component=server -o jsonpath="{.items[0].metadata.name}" 2>/dev/null || true)
    if [[ -n "$POD_NAME" ]]; then
      STATUS=$(kubectl get pod -n "$NAMESPACE" "$POD_NAME" -o jsonpath="{.status.phase}")
      READY_STATUS=$(kubectl get pod -n "$NAMESPACE" "$POD_NAME" -o jsonpath="{.status.containerStatuses[0].ready}" 2>/dev/null || true)
      if [[ "$STATUS" == "Running" && "$READY_STATUS" == "true" ]]; then
        echo "✅ [$CONTEXT] Prometheus rodando no pod '$POD_NAME'."
        break
      fi
      echo "⌛ [$CONTEXT] Pod: $POD_NAME - Status: $STATUS, Ready: $READY_STATUS"
    else
      echo "⌛ [$CONTEXT] Nenhum pod Prometheus encontrado ainda..."
    fi
    sleep "$SLEEP_TIME"
  done
done

echo "🎉 Prometheus instalado com sucesso em member1 e member2."
