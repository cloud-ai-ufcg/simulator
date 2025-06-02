#!/bin/bash
set -e

# Color (Yellow for this script)
COLOR="\033[1;33m"
RESET="\033[0m"

echo -e "${COLOR}🚀 Starting local Karmada environment...${RESET}"
if [ ! -d "karmada" ]; then
  echo -e "${COLOR}[INFO] Cloning Karmada repository...${RESET}"
  git clone https://github.com/karmada-io/karmada.git
else
  echo -e "${COLOR}[INFO] Karmada repository already exists. Skipping clone.${RESET}"
fi
cd karmada
sudo sysctl fs.inotify.max_user_watches=524288
sudo sysctl fs.inotify.max_user_instances=512
hack/local-up-karmada.sh
cd ..

echo -e "${COLOR}🔧 Setting KUBECONFIG to karmada-apiserver...${RESET}"
export KUBECONFIG=~/.kube/karmada.config
kubectl config use-context karmada-apiserver

echo -e "${COLOR}🏷️ Labeling clusters...${RESET}"
kubectl label cluster member1 cloud=private --overwrite
kubectl label cluster member2 cloud=public --overwrite

echo -e "${COLOR}📦 Checking if propagation policies already exist...${RESET}"
if ! kubectl get clusterpropagationpolicy deploy-private >/dev/null 2>&1; then
  echo -e "${COLOR}🔧 Creating propagation policies...${RESET}"
  kubectl create -f clusterpropagationpolicy.yaml
else
  echo -e "${COLOR}✅ Propagation policies already exist. Skipping creation.${RESET}"
fi

echo -e "${COLOR}🧹 Removing cluster member3...${RESET}"
export KUBECONFIG=~/.kube/members.config
kubectl config delete-context member3 || true
kubectl config delete-cluster kind-member3 || true

CONTAINER_ID=$(docker ps -q --filter "name=kind-member3")
if [ -n "$CONTAINER_ID" ]; then
  echo -e "${COLOR}🧹 Stopping container $CONTAINER_ID for cluster member3...${RESET}"
  docker stop "$CONTAINER_ID"
  docker rm "$CONTAINER_ID"
else
  echo -e "${COLOR}ℹ️ Container kind-member3 is not running.${RESET}"
fi
