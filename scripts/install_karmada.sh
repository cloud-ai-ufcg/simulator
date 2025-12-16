#!/bin/bash
# -----------------------------------------------------------------------------
# Karmada Local Bootstrap – initializes local Karmada environment, labels clusters,
# and applies ClusterPropagationPolicies. Also removes legacy member3 artifacts.
# -----------------------------------------------------------------------------
# ‣ Behaviour
#   • Clones Karmada repo if absent.
#   • Launches control-plane via hack/local-up-karmada.sh.
#   • Configures kubecontext and labels clusters.
#   • Removes member3 context and container if found.
#   • Validates kubectl connectivity through Karmada.
# -----------------------------------------------------------------------------
#   Colour palette
# -----------------------------------------------------------------------------
COLOR="\033[1;33m"  # Yellow – this script's identity color
RESET="\033[0m"

set -e
trap 'echo -e "${COLOR}❌  Error in ${BASH_SOURCE[0]}:$LINENO – $BASH_COMMAND${RESET}"' ERR

# -----------------------------------------------------------------------------
# 0. Ensure Go is in PATH (needed for Karmada build)
# ------------------------------------------------------------------------------
if [ -f /usr/local/go/bin/go ] && ! command -v go &> /dev/null; then
  export PATH=$PATH:/usr/local/go/bin
fi

# -----------------------------------------------------------------------------
# 1. Clone and launch Karmada control plane
# ------------------------------------------------------------------------------
KARMADA_RELEASE=v1.14.1

# Ensure user has docker permissions before using docker commands
echo -e "${COLOR}🔍 Checking docker permissions...${RESET}"
if ! docker ps &>/dev/null; then
  echo -e "${COLOR}⚠️  Docker permission check failed. Ensuring user has docker group access...${RESET}"
  CURRENT_USER=$(whoami)
  
  if ! groups | grep -q docker; then
    echo -e "${COLOR}➕ Adding user $CURRENT_USER to docker group...${RESET}"
    sudo usermod -aG docker "$CURRENT_USER"
    echo -e "${COLOR}✅ User added to docker group.${RESET}"
  else
    echo -e "${COLOR}ℹ️  User is already in docker group.${RESET}"
  fi
  
  echo -e "${COLOR}ℹ️  Docker group membership requires a new login session to take effect.${RESET}"
  echo -e "${COLOR}ℹ️  Options:${RESET}"
  echo -e "${COLOR}   1. Run 'newgrp docker' in a new terminal and re-run this script${RESET}"
  echo -e "${COLOR}   2. Logout and login again, then re-run this script${RESET}"
  echo -e "${COLOR}⚠️  Exiting. Please activate docker group and re-run this script.${RESET}"
  exit 1
else
  echo -e "${COLOR}✅ Docker permissions OK.${RESET}"
fi

echo -e "${COLOR}🚀 Starting local Karmada environment...${RESET}"
if [ ! -d "karmada" ]; then
  echo -e "${COLOR}[INFO] Cloning Karmada repository...${RESET}"
  git clone --branch $KARMADA_RELEASE --depth 1 https://github.com/karmada-io/karmada.git
else
  echo -e "${COLOR}[INFO] Karmada repository already exists. Skipping clone.${RESET}"
fi

cd karmada
# Only set inotify limits on Linux (not needed on macOS)
if [[ "$(uname)" == "Linux" ]]; then
  sudo sysctl fs.inotify.max_user_watches=524288
  sudo sysctl fs.inotify.max_user_instances=512
fi
  # Ensure /tmp/karmada is owned by the current user to avoid permission
  # errors inside Karmada's local-up script when cleaning temporary logs.
  if [ -d /tmp/karmada ]; then
    sudo chown -R "$(id -un)":"$(id -gn)" /tmp/karmada 2>/dev/null || true
  fi

bash hack/local-up-karmada.sh
cd ..

# -----------------------------------------------------------------------------
# 2. Configure kubecontext and label clusters
# -----------------------------------------------------------------------------
echo -e "${COLOR}🔧 Setting KUBECONFIG to karmada-apiserver...${RESET}"
export KUBECONFIG=~/.kube/karmada.config
kubectl config use-context karmada-apiserver

echo -e "${COLOR}🏷️  Labeling clusters...${RESET}"
kubectl label cluster member1 cloud=private --overwrite
kubectl label cluster member2 cloud=public --overwrite

# -----------------------------------------------------------------------------
# 3. Apply ClusterPropagationPolicies if not already present
# -----------------------------------------------------------------------------
echo -e "${COLOR}📦 Checking if propagation policies already exist...${RESET}"
if ! kubectl get clusterpropagationpolicy deploy-private >/dev/null 2>&1; then
  echo -e "${COLOR}🔧 Creating propagation policies...${RESET}"
  kubectl create -f clusterpropagationpolicy.yaml
else
  echo -e "${COLOR}✅ Propagation policies already exist. Skipping creation.${RESET}"
fi

# -----------------------------------------------------------------------------
# 4. Cleanup: remove legacy member3 context and container
# -----------------------------------------------------------------------------
echo -e "${COLOR}🧹 Removing cluster member3...${RESET}"
export KUBECONFIG=~/.kube/members.config
kubectl config delete-context member3 || true
kubectl config delete-cluster kind-member3 || true

# Docker permissions were already verified in section 1, so we can use docker directly
CONTAINER_ID=$(docker ps -q --filter "name=member3-control-plane")
if [ -n "$CONTAINER_ID" ]; then
  echo -e "${COLOR}🧹 Stopping container $CONTAINER_ID for cluster member3...${RESET}"
  docker stop "$CONTAINER_ID"
  docker rm "$CONTAINER_ID"
else
  echo -e "${COLOR}ℹ️ Container kind-member3 is not running.${RESET}"
fi

# -----------------------------------------------------------------------------
# 5. Validate kubectl connectivity through karmada-apiserver
# -----------------------------------------------------------------------------
echo -e "${COLOR}[⏳] Verifying kubectl access...${RESET}"
for i in {1..30}; do
  kubectl version --client &>/dev/null && kubectl get nodes &>/dev/null && {
    echo -e "${COLOR}[✅] kubectl works.${RESET}"
    break
  }
  echo -e "${COLOR}[...] Attempt $i: waiting (3 s)...${RESET}"
  sleep 3
done