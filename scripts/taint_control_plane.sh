#!/bin/bash
# -----------------------------------------------------------------------------
# Control Plane Tainter – applies NoSchedule taint to control-plane nodes
# in both member1 and member2 clusters to prevent workload scheduling.
# -----------------------------------------------------------------------------
# ‣ Behaviour
#   • Detects control-plane node in each cluster.
#   • Applies `NoSchedule` taint to avoid KWOK scheduling onto them.
# -----------------------------------------------------------------------------
COLOR="\033[1;34m"  # Blue – this script's identity color
RESET="\033[0m"

set -euo pipefail
trap 'echo -e "${COLOR}❌ Error in ${BASH_SOURCE[0]}:$LINENO – $BASH_COMMAND${RESET}"' ERR

export KUBECONFIG=~/.kube/members.config

# -----------------------------------------------------------------------------
# 1. Taint control-plane node in member2
# -----------------------------------------------------------------------------
echo -e "${COLOR}[1/2] Tainting control-plane node of member2...${RESET}"
CONTROL_PLANE_M2=$(kubectl get nodes -o name --context member2 | grep control-plane | sed 's|node/||')
kubectl taint nodes "$CONTROL_PLANE_M2" node-role.kubernetes.io/control-plane=:NoSchedule --context member2 --overwrite

# -----------------------------------------------------------------------------
# 2. Taint control-plane node in member1
# -----------------------------------------------------------------------------
echo -e "${COLOR}[2/2] Tainting control-plane node of member1...${RESET}"
CONTROL_PLANE_M1=$(kubectl get nodes -o name --context member1 | grep control-plane | sed 's|node/||')
kubectl taint nodes "$CONTROL_PLANE_M1" node-role.kubernetes.io/control-plane=:NoSchedule --context member1 --overwrite

echo -e "${COLOR}✅ Control-plane taints applied successfully.${RESET}"