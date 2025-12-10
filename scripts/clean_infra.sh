#!/bin/bash
# Simple infra cleanup script: remove simulator workloads and KWOK nodes
# without destroying KIND clusters or Karmada.

set -euo pipefail

COLOR="\033[1;32m"
RESET="\033[0m"

echo -e "${COLOR}🧹 Cleaning Kubernetes infrastructure (workloads + KWOK nodes)...${RESET}"

# -----------------------------------------------------------------------------
# 1) Clean workloads federated via Karmada (karmada-apiserver)
# -----------------------------------------------------------------------------
export KUBECONFIG=~/.kube/karmada.config

if kubectl config use-context karmada-apiserver >/dev/null 2>&1; then
  echo -e "${COLOR}➡️  Cleaning deployments/jobs/pods in Karmada (namespace default)...${RESET}"
  kubectl delete deployment --all -n default || true
  kubectl delete job --all -n default || true
  kubectl delete pod --all -n default || true
else
  echo -e "${COLOR}⚠️  Context 'karmada-apiserver' not found. Skipping Karmada cleanup.${RESET}"
fi

# -----------------------------------------------------------------------------
# 2) Remove KWOK fake nodes and workloads directly in member clusters
# -----------------------------------------------------------------------------
export KUBECONFIG=~/.kube/members.config

for ctx in member1 member2; do
  if kubectl config use-context "$ctx" >/dev/null 2>&1; then
    echo -e "${COLOR}➡️  Removing KWOK nodes in $ctx (label type=kwok)...${RESET}"
    kubectl delete node -l type=kwok --context "$ctx" --ignore-not-found || true

    echo -e "${COLOR}➡️  Cleaning workloads in $ctx (namespace default)...${RESET}"
    kubectl delete deployment --all -n default --context "$ctx" || true
    kubectl delete job --all -n default --context "$ctx" || true
    kubectl delete pod --all -n default --context "$ctx" || true
  else
    echo -e "${COLOR}⚠️  Context '$ctx' not found. Skipping this cluster.${RESET}"
  fi
done

echo -e "${COLOR}✅ Infrastructure cleaned (clusters preserved).${RESET}"
