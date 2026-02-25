#!/bin/bash
# Cleanup script: remove only workloads (deployments, jobs, pods)
# WITHOUT removing KWOK nodes or destroying KIND clusters/Karmada.
# Deletes ONLY via Karmada API server to prevent reconciliation loops.

set -euo pipefail

COLOR="\033[1;32m"
RESET="\033[0m"

echo -e "${COLOR}🧹 Cleaning workloads via Karmada (deployments/jobs/pods only)...${RESET}"

# Check if infra-environment container is running
if ! docker ps --format '{{.Names}}' | grep -q '^infra-environment$'; then
  echo -e "${COLOR}❌ Container 'infra-environment' is not running.${RESET}"
  exit 1
fi

echo -e "${COLOR}🎯 Accessing infra-environment container...${RESET}"

# Execute cleanup commands inside the infra-environment container
docker exec infra-environment bash -c '
  export KUBECONFIG=~/.kube/karmada.config
  
  # Find the correct Karmada context
  KARMADA_CONTEXT=""
  for ctx in karmada-apiserver karmada karmada-host; do
    if kubectl config get-contexts "$ctx" >/dev/null 2>&1; then
      KARMADA_CONTEXT="$ctx"
      break
    fi
  done
  
  if [ -z "$KARMADA_CONTEXT" ]; then
    echo "⚠️  Karmada context not found"
    exit 1
  fi
  
  echo "🎯 Using Karmada context: $KARMADA_CONTEXT"
  
  echo "➡️  Deleting deployments in Karmada (namespace default)..."
  kubectl delete deployment --all -n default --context "$KARMADA_CONTEXT" || true
  
  echo "➡️  Deleting jobs in Karmada (namespace default)..."
  kubectl delete job --all -n default --context "$KARMADA_CONTEXT" || true
  
  echo "➡️  Deleting pods in Karmada (namespace default)..."
  kubectl delete pod --all -n default --context "$KARMADA_CONTEXT" || true
'

echo -e "${COLOR}⏳  Waiting for Karmada to propagate deletions to member clusters...${RESET}"
sleep 3

echo -e "${COLOR}✅ Workloads deleted via Karmada (nodes and clusters preserved).${RESET}"
