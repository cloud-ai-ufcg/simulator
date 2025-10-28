#!/bin/bash
# -----------------------------------------------------------------------------
# KWOK Mode Setup – prepares environment for simulated workloads
# -----------------------------------------------------------------------------
# ‣ Behaviour
#   • Installs KWOK controllers
#   • Creates fake nodes
#   • Applies KWOK configurations
# -----------------------------------------------------------------------------
COLOR="\033[1;34m"  # Blue – this script's identity color
RESET="\033[0m"

set -euo pipefail

echo -e "${COLOR}🎭 KWOK Mode Setup${RESET}"

export KUBECONFIG=~/.kube/members.config

# 1. Install KWOK
echo -e "${COLOR}[1/3] Installing KWOK controller...${RESET}"
./install_kwok.sh

# 2. Create fake nodes
echo -e "${COLOR}[2/3] Creating KWOK fake nodes...${RESET}"
./create_kwok_nodes.sh

# 3. Apply taints
echo -e "${COLOR}[3/3] Applying control-plane taints...${RESET}"
./taint_control_plane.sh

echo -e "${COLOR}✅ KWOK mode setup completed!${RESET}"
