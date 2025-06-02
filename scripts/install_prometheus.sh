#!/bin/bash
set -euo pipefail

# Color (Cyan for this script)
COLOR="\033[1;36m"
RESET="\033[0m"

RELEASE_NAME="prometheus"
NAMESPACE="monitoring"
SLEEP_TIME=${SLEEP_TIME:-5}

export KUBECONFIG=~/.kube/members.config

for CONTEXT in member1 member2; do
  echo -e "${COLOR}⛵ [$CONTEXT] Installing Prometheus...${RESET}"

  kubectl config use-context "$CONTEXT"

  echo -e "${COLOR}🔧 Creating namespace '$NAMESPACE' (if needed)...${RESET}"
  kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

  echo -e "${COLOR}📦 Configuring Helm...${RESET}"
  helm repo add prometheus-community https://prometheus-community.github.io/helm-charts || true
  helm repo update

  echo -e "${COLOR}🧹 Removing old release (if any)...${RESET}"
  helm uninstall "$RELEASE_NAME" -n "$NAMESPACE" || true

  echo -e "${COLOR}🚀 Installing Prometheus via Helm in context $CONTEXT...${RESET}"
  helm upgrade --install "$RELEASE_NAME" prometheus-community/prometheus \
    --namespace "$NAMESPACE" \
    --wait \
    --set alertmanager.enabled=false \
    --set pushgateway.enabled=false \
    --set server.persistentVolume.enabled=false \
    --set server.service.type=ClusterIP

  echo -e "${COLOR}⏳ Waiting for Prometheus to run in cluster $CONTEXT...${RESET}"
  for i in {1..40}; do
    POD_NAME=$(kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=prometheus,app.kubernetes.io/component=server -o jsonpath="{.items[0].metadata.name}" 2>/dev/null || true)
    if [[ -n "$POD_NAME" ]]; then
      STATUS=$(kubectl get pod -n "$NAMESPACE" "$POD_NAME" -o jsonpath="{.status.phase}")
      READY_STATUS=$(kubectl get pod -n "$NAMESPACE" "$POD_NAME" -o jsonpath="{.status.containerStatuses[0].ready}" 2>/dev/null || true)
      if [[ "$STATUS" == "Running" && "$READY_STATUS" == "true" ]]; then
        echo -e "${COLOR}✅ [$CONTEXT] Prometheus is running in pod '$POD_NAME'.${RESET}"
        break
      fi
      echo -e "${COLOR}⌛ [$CONTEXT] Pod: $POD_NAME - Status: $STATUS, Ready: $READY_STATUS${RESET}"
    else
      echo -e "${COLOR}⌛ [$CONTEXT] No Prometheus pod found yet...${RESET}"
    fi
    sleep "$SLEEP_TIME"
  done
done

echo -e "${COLOR}🎉 Prometheus successfully installed in member1 and member2.${RESET}"
