#!/bin/bash

# -----------------------------------------------------------------------------
# Fix Karmada Clusters - Diagnose and fix cluster registration issues
# -----------------------------------------------------------------------------

set -euo pipefail

COLOR="\033[1;36m"  # Cyan
RESET="\033[0m"

echo -e "${COLOR}🔍 Diagnosing Karmada cluster issues...${RESET}"

export KUBECONFIG=~/.kube/karmada.config
kubectl config use-context karmada-apiserver

echo -e "\n${COLOR}[1/6] Checking cluster status...${RESET}"
kubectl get clusters

echo -e "\n${COLOR}[2/6] Checking cluster details...${RESET}"
for cluster in member1 member2; do
    echo -e "\n${COLOR}Cluster: $cluster${RESET}"
    kubectl describe cluster $cluster | grep -A5 "Ready:"
done

echo -e "\n${COLOR}[3/6] Checking deployments in karmada apiserver...${RESET}"
kubectl get deployments -n default

echo -e "\n${COLOR}[4/6] Checking ResourceBindings...${RESET}"
kubectl get resourcebindings -A | head -10

echo -e "\n${COLOR}[5/6] Checking if clusters can be reached...${RESET}"
for cluster in member1 member2; do
    echo -e "\n${COLOR}Testing: $cluster${RESET}"
    kubectl --kubeconfig=$(kind get kubeconfig --name $cluster | head -1) get nodes 2>&1 | head -5
done

echo -e "\n${COLOR}[6/6] Deployment annotations in karmada...${RESET}"
kubectl get deployments -n default -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.metadata.labels.cloud}{"\t"}{.metadata.annotations.clusterpropagationpolicy\.karmada\.io/name}{"\n"}{end}'

echo -e "\n${COLOR}✅ Diagnosis complete!${RESET}"
