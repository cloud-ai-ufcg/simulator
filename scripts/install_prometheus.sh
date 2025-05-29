#!/bin/bash
set -e

NAMESPACE=monitoring
RELEASE_NAME=prometheus
SLEEP_TIME=${SLEEP_TIME:-5}

echo "⏳ Verificando contexto atual..."
CURRENT_CONTEXT=$(kubectl config current-context)
echo "📌 Contexto ativo: $CURRENT_CONTEXT"

echo "🔍 Selecionando nó real (worker)..."
REAL_NODE=$(kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' \
  | grep -E 'teste-worker' \
  | head -n 1)

if [[ -z "$REAL_NODE" ]]; then
  echo "❌ Nenhum nó 'kind-worker' encontrado. Verifique se o cluster possui um worker real."
  exit 1
else
  echo "✅ Usando nó worker real: $REAL_NODE"
fi

echo "🔧 Criando namespace '$NAMESPACE'..."
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

echo "📦 Configurando Helm..."
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts || true
helm repo update

echo "🧹 Removendo release anterior (se existir)..."
helm uninstall "$RELEASE_NAME" -n "$NAMESPACE" || true

echo "🚀 Instalando Prometheus no nó real '$REAL_NODE'..."
helm upgrade --install "$RELEASE_NAME" prometheus-community/prometheus \
  --namespace "$NAMESPACE" \
  --wait \
  --debug \
  --set alertmanager.enabled=false \
  --set pushgateway.enabled=false \
  --set server.persistentVolume.enabled=false \
  --set server.service.type=NodePort \
  --set server.service.nodePort=30090 \
  \
  --set server.nodeSelector."kubernetes\.io/hostname"="$REAL_NODE" \
  --set kubeStateMetrics.nodeSelector."kubernetes\.io/hostname"="$REAL_NODE" \
  --set alertmanager.nodeSelector."kubernetes\.io/hostname"="$REAL_NODE" \
  --set pushgateway.nodeSelector."kubernetes\.io/hostname"="$REAL_NODE" \
  --set prometheusNodeExporter.nodeSelector."kubernetes\.io/hostname"="$REAL_NODE"

echo "⏳ Aguardando Prometheus iniciar..."
for i in {1..40}; do
  POD_NAME=$(kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=prometheus,app.kubernetes.io/component=server -o jsonpath="{.items[0].metadata.name}" 2>/dev/null || true)
  if [[ -n "$POD_NAME" ]]; then
    STATUS=$(kubectl get pod -n "$NAMESPACE" "$POD_NAME" -o jsonpath="{.status.phase}")
    READY_STATUS=$(kubectl get pod -n "$NAMESPACE" "$POD_NAME" -o jsonpath="{.status.containerStatuses[0].ready}" 2>/dev/null || true)
    if [[ "$STATUS" == "Running" && "$READY_STATUS" == "true" ]]; then
      echo "✅ Prometheus Server '$POD_NAME' está rodando."
      break
    else
      echo "⌛ Pod encontrado: $POD_NAME. Status atual: $STATUS, Ready: $READY_STATUS. Tentando novamente em ${SLEEP_TIME}s..."
    fi
  else
    echo "⌛ Nenhum pod 'prometheus-server' encontrado ainda. Tentando novamente em ${SLEEP_TIME}s..."
  fi
  sleep "$SLEEP_TIME"
done

POD_NAME=$(kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=prometheus,app.kubernetes.io/component=server -o jsonpath="{.items[0].metadata.name}" 2>/dev/null || true)
if [[ -z "$POD_NAME" ]]; then
  echo "❌ Prometheus Server não subiu após o tempo limite. Verifique os logs de pod."
  exit 1
fi

echo "🌐 Para acessar Prometheus localmente:"
echo "kubectl port-forward -n $NAMESPACE svc/$RELEASE_NAME-server 9090:80"
echo "Depois, acesse http://localhost:9090"

