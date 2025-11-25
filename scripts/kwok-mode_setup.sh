#!/bin/bash
# -----------------------------------------------------------------------------
# KWOK Mode Setup – prepares environment for simulated workloads
# -----------------------------------------------------------------------------
# ‣ Behaviour
#   • Installs KWOK controllers
#   • Creates fake nodes
#   • Does NOT apply taints (Prometheus must be installed first)
# -----------------------------------------------------------------------------
COLOR="\033[1;34m"  # Blue – this script's identity color
RESET="\033[0m"

set -euo pipefail

echo -e "${COLOR}🎭 KWOK Mode Setup${RESET}"

export KUBECONFIG=~/.kube/members.config

# 1. Install KWOK
echo -e "${COLOR}[1/2] Installing KWOK controller...${RESET}"
./install_kwok.sh

# 2. Create fake nodes
echo -e "${COLOR}[2/2] Creating KWOK fake nodes...${RESET}"
./create_kwok_nodes.sh

# Note: Taints are applied AFTER Prometheus installation (in main.sh)
# This ensures Prometheus pods can be scheduled on control-plane

echo -e "${COLOR}✅ KWOK mode setup completed!${RESET}"
