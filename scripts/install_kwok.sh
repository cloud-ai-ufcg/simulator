    #!/bin/bash
# -----------------------------------------------------------------------------
# KWOK Installer – installs the KWOK controller and stage-fast template
# in both member1 and member2 clusters from the latest official release.
# -----------------------------------------------------------------------------
# ‣ Behaviour
#   • Detects latest KWOK release from GitHub.
#   • Applies KWOK and stage-fast YAML manifests to both clusters.
#   • Waits for the kwok-controller rollout to complete.
# -----------------------------------------------------------------------------
#   Colour palette
# -----------------------------------------------------------------------------
COLOR="\033[1;34m"  # Blue – this script's identity color
RESET="\033[0m"

set -euo pipefail
trap 'echo -e "${COLOR}❌ Error in ${BASH_SOURCE[0]}:$LINENO – $BASH_COMMAND${RESET}"' ERR

# -----------------------------------------------------------------------------
# 0. Configuration
# -----------------------------------------------------------------------------
export KUBECONFIG=~/.kube/members.config
KWOK_REPO="kubernetes-sigs/kwok"
KWOK_LATEST_RELEASE=$(curl -s "https://api.github.com/repos/${KWOK_REPO}/releases/latest" | jq -r '.tag_name')

# -----------------------------------------------------------------------------
# 1. Install KWOK on member1
# -----------------------------------------------------------------------------
echo -e "${COLOR}[1/2] Installing KWOK on member1...${RESET}"
kubectl config use-context member1

kubectl apply -f "https://github.com/${KWOK_REPO}/releases/download/${KWOK_LATEST_RELEASE}/kwok.yaml" --context member1
kubectl apply -f "https://github.com/${KWOK_REPO}/releases/download/${KWOK_LATEST_RELEASE}/stage-fast.yaml" --context member1

KWOK_NAMESPACE_M1=$(kubectl get deployment --context member1 --all-namespaces | grep kwok-controller | awk '{print $1}')
kubectl rollout status deployment/kwok-controller -n "$KWOK_NAMESPACE_M1" --context member1 --timeout=120s

# -----------------------------------------------------------------------------
# 2. Install KWOK on member2
# -----------------------------------------------------------------------------
echo -e "${COLOR}[2/2] Installing KWOK on member2...${RESET}"
kubectl config use-context member2

kubectl apply -f "https://github.com/${KWOK_REPO}/releases/download/${KWOK_LATEST_RELEASE}/kwok.yaml"
kubectl apply -f "https://github.com/${KWOK_REPO}/releases/download/${KWOK_LATEST_RELEASE}/stage-fast.yaml"

KWOK_NAMESPACE_M2=$(kubectl get deployment --all-namespaces | grep kwok-controller | awk '{print $1}')
kubectl rollout status deployment/kwok-controller -n "$KWOK_NAMESPACE_M2" --timeout=120s

echo -e "${COLOR}✅ KWOK successfully installed on both clusters.${RESET}"