#!/bin/bash
set -euo pipefail

# Color (Red for this script)
COLOR="\033[1;31m"
RESET="\033[0m"

# Ensure execution permissions for all required scripts
chmod +x install_prerequisites.sh generate_manifests.sh install_karmada.sh install_prometheus.sh ASsetup.sh

echo -e "${COLOR}[1/5] 📦 Installing prerequisites...${RESET}"
./install_prerequisites.sh

echo -e "${COLOR}[2/5] 📝 Generating configuration files (manifests)...${RESET}"
./generate_manifests.sh

echo -e "${COLOR}[3/5] ☸️ Bringing up Karmada environment...${RESET}"
./install_karmada.sh

export KUBECONFIG=~/.kube/karmada.config

# Wait for kubectl to respond
echo -e "${COLOR}[⏳] Verifying kubectl access...${RESET}"
for i in {1..30}; do
  if kubectl version --client &> /dev/null && kubectl get nodes &> /dev/null; then
    echo -e "${COLOR}[✅] kubectl is working and cluster is accessible.${RESET}"
    break
  fi
  echo -e "${COLOR}[...] Attempt $i: waiting for cluster (3s)...${RESET}"
  sleep 3
done

# Wait for at least one node to be Ready
echo -e "${COLOR}[⏳] Checking if any node in the cluster is Ready...${RESET}"
for i in {1..20}; do
  if kubectl get nodes | grep -q " Ready"; then
    echo -e "${COLOR}[✅] At least one node is Ready.${RESET}"
    break
  fi
  echo -e "${COLOR}[...] Attempt $i: waiting for a Ready node (3s)...${RESET}"
  sleep 3
done

echo -e "${COLOR}[4/5] 📊 Installing Prometheus...${RESET}"
./install_prometheus.sh

# Wait for Prometheus server pod to be running
echo -e "${COLOR}[⏳] Checking if Prometheus is running...${RESET}"
for i in {1..30}; do
  STATUS=$(kubectl get pod -n monitoring -l app.kubernetes.io/name=prometheus,app.kubernetes.io/component=server \
    -o jsonpath="{.items[0].status.phase}" 2>/dev/null || echo "NotFound")
  READY=$(kubectl get pod -n monitoring -l app.kubernetes.io/name=prometheus,app.kubernetes.io/component=server \
    -o jsonpath="{.items[0].status.containerStatuses[0].ready}" 2>/dev/null || echo "false")
  if [[ "$STATUS" == "Running" && "$READY" == "true" ]]; then
    echo -e "${COLOR}[✅] Prometheus is running correctly.${RESET}"
    break
  fi
  echo -e "${COLOR}[...] Attempt $i: waiting for Prometheus to be ready (3s)...${RESET}"
  sleep 3
done

echo -e "${COLOR}[5/5] ⚙️ Applying Cluster Autoscaler configuration...${RESET}"
./ASsetup.sh

echo ""
echo -e "${COLOR}[🎉] Kubernetes environment with Karmada and Autoscaler provisioned successfully!${RESET}"
