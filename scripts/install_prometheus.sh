#!/bin/bash
# -----------------------------------------------------------------------------
# Prometheus Installer – deploys Prometheus via Helm in both member clusters.
# Also sets up port-forwards for local access to Prometheus UIs.
# -----------------------------------------------------------------------------
# ‣ Behaviour
#   • Installs Prometheus in `member1` and `member2` clusters.
#   • Waits for pods to be fully running and ready.
#   • Starts background port-forwards for each cluster.
# -----------------------------------------------------------------------------
#   Colour palette
# -----------------------------------------------------------------------------
COLOR="\033[1;36m"  # Cyan – this script's identity color
RESET="\033[0m"

set -euo pipefail
trap 'echo -e "\033[1;31m❌ Error in $BASH_SOURCE:$LINENO – $BASH_COMMAND\033[0m"' ERR

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------
RELEASE_NAME="prometheus"
NAMESPACE="monitoring"
SLEEP_TIME=${SLEEP_TIME:-5}

PORT_FORWARD_NAMESPACE="$NAMESPACE"
PORT_FORWARD_SERVICE="prometheus-server"
PORT_FORWARD_TARGET_PORT=80
declare -A PF_PORTS=([member1]=9090 [member2]=9091)

export KUBECONFIG=~/.kube/members.config

# -----------------------------------------------------------------------------
# 1. Install / upgrade Prometheus in both clusters
# -----------------------------------------------------------------------------
for CONTEXT in member1 member2; do
  echo -e "${COLOR}⛵ [$CONTEXT] Installing Prometheus...${RESET}"
  kubectl config use-context "$CONTEXT"

  echo -e "${COLOR}🔧 Creating namespace '$NAMESPACE' (if needed)...${RESET}"
  kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

  echo -e "${COLOR}📦 Configuring Helm repository...${RESET}"
  helm repo add prometheus-community https://prometheus-community.github.io/helm-charts || true
  helm repo update >/dev/null 2>&1 || {
    echo -e "${COLOR}⚠️ helm repo update failed – retrying in 5 s${RESET}"
    sleep 5
    helm repo update >/dev/null 2>&1
  }

  echo -e "${COLOR}🧹 Removing old Prometheus release (if any)...${RESET}"
  helm uninstall "$RELEASE_NAME" -n "$NAMESPACE" >/dev/null 2>&1 || true

  echo -e "${COLOR}🚀 Installing Prometheus via Helm...${RESET}"
  helm upgrade --install "$RELEASE_NAME" prometheus-community/prometheus \
      --namespace "$NAMESPACE" --wait \
      --set alertmanager.enabled=false \
      --set pushgateway.enabled=false \
      --set server.persistentVolume.enabled=false \
      --set server.service.type=ClusterIP

  echo -e "${COLOR}⏳ Waiting for Prometheus to run in cluster '$CONTEXT'...${RESET}"
  set +e
  for i in {1..40}; do
    POD=$(kubectl get pods -n "$NAMESPACE" \
          -l app.kubernetes.io/name=prometheus,app.kubernetes.io/component=server \
          -o jsonpath="{.items[0].metadata.name}" 2>/dev/null)
    if [[ -n "$POD" ]]; then
      PHASE=$(kubectl get pod -n "$NAMESPACE" "$POD" -o jsonpath="{.status.phase}" 2>/dev/null)
      READY=$(kubectl get pod -n "$NAMESPACE" "$POD" -o jsonpath="{.status.containerStatuses[0].ready}" 2>/dev/null)
      [[ "$PHASE" == "Running" && "$READY" == "true" ]] && {
        echo -e "${COLOR}✅ [$CONTEXT] Prometheus is running in pod '$POD'.${RESET}"
        break
      }
      echo -e "${COLOR}⌛ [$CONTEXT] Pod: $POD – Status: $PHASE, Ready: $READY${RESET}"
    else
      echo -e "${COLOR}⌛ [$CONTEXT] No Prometheus pod found yet...${RESET}"
    fi
    sleep "$SLEEP_TIME"
  done
  set -e
done

echo -e "${COLOR}🎉 Prometheus successfully installed in member1 and member2.${RESET}"

# -----------------------------------------------------------------------------
# 2. Global readiness check (reference: member1)
# -----------------------------------------------------------------------------
echo -e "${COLOR}[⏳] Checking Prometheus readiness (global)...${RESET}"
set +e
for i in {1..30}; do
  STATUS=$(kubectl --context member1 -n "$NAMESPACE" \
           get pod -l app.kubernetes.io/name=prometheus,app.kubernetes.io/component=server \
           -o jsonpath="{.items[0].status.phase}" 2>/dev/null)
  READY=$(kubectl --context member1 -n "$NAMESPACE" \
           get pod -l app.kubernetes.io/name=prometheus,app.kubernetes.io/component=server \
           -o jsonpath="{.items[0].status.containerStatuses[0].ready}" 2>/dev/null)
  [[ "$STATUS" == "Running" && "$READY" == "true" ]] && {
    echo -e "${COLOR}[✅] Prometheus is running correctly (verified on member1).${RESET}"
    break
  }
  echo -e "${COLOR}[...] Attempt $i: waiting for Prometheus to be ready (5 s)...${RESET}"
  sleep 5
done
set -e

# -----------------------------------------------------------------------------
# 3. Start background port-forwards for Prometheus dashboards
# -----------------------------------------------------------------------------
start_port_forward() {
  local ctx=$1 port=$2 svc="$PORT_FORWARD_SERVICE" ns="$PORT_FORWARD_NAMESPACE"
  kubectl --context "$ctx" -n "$ns" get svc "$svc" &>/dev/null || {
    echo -e "${COLOR}⚠️ [$ctx] Service not found – skipping port-forward.${RESET}"
    return
  }

  (
    set +e
    while true; do
      kubectl --context "$ctx" -n "$ns" port-forward "svc/$svc" "$port:$PORT_FORWARD_TARGET_PORT" --address 127.0.0.1 >/dev/null 2>&1
      sleep 2
    done
  ) &
}

echo -e "${COLOR}🔁 Starting Prometheus port-forwards...${RESET}"
for ctx in "${!PF_PORTS[@]}"; do
  echo -e "${COLOR}🌐 $ctx → http://localhost:${PF_PORTS[$ctx]}${RESET}"
  start_port_forward "$ctx" "${PF_PORTS[$ctx]}"
done

echo -e "${COLOR}✅ Port-forwards in background.${RESET}"