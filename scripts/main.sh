#!/bin/bash
# -----------------------------------------------------------------------------
# Main Orchestrator – provisions the full simulation stack using Karmada,
# KWOK, Cluster Autoscaler, and Prometheus, driven by a YAML config file.
# -----------------------------------------------------------------------------
# ‣ Behaviour
#   • Loads cluster definitions from initialization.yaml.
#   • Installs prerequisites, generates manifests, starts Karmada.
#   • Deploys Prometheus, KWOK, Cluster Autoscaler (conditionally), and nodes.
#   • Supports both KWOK (simulated) and real workload modes
# -----------------------------------------------------------------------------
COLOR="\033[1;32m"  # Green – this script's identity color
RESET="\033[0m"

set -euo pipefail
trap 'echo -e "${COLOR}❌ Error in ${BASH_SOURCE[0]}:$LINENO – $BASH_COMMAND${RESET}"' ERR

# -----------------------------------------------------------------------------
# Load execution mode configuration
# -----------------------------------------------------------------------------
if [ -f "mode.env" ]; then
    source mode.env
else
    # Default to KWOK mode if mode.env doesn't exist
    EXECUTION_MODE="kwok"
fi

echo -e "${COLOR}🎯 Execution Mode: ${EXECUTION_MODE}${RESET}"

# -----------------------------------------------------------------------------
# Setup Python venv and dependencies for Analyzer
# -----------------------------------------------------------------------------
echo -e "${COLOR}🐍 Setting up Python venv for Analyzer...${RESET}"
SCRIPT_DIR="$(dirname "$0")"
pushd "$SCRIPT_DIR" > /dev/null
chmod +x setup_venv.sh
./setup_venv.sh
popd > /dev/null
echo -e "${COLOR}✅ Python venv ready.${RESET}"

# -----------------------------------------------------------------------------
# 1. Ensure all scripts are executable
# -----------------------------------------------------------------------------
chmod +x install_prerequisites.sh generate_manifests.sh install_karmada.sh \
        install_prometheus.sh install_kwok.sh install_autoscaler.sh \
        install_autoscaler_kind.sh taint_control_plane.sh create_kwok_nodes.sh \
        create_kind_clusters.sh create_real_nodes.sh real-mode_setup.sh kwok-mode_setup.sh \
        load_config.sh

echo -e "${COLOR}[1/8] 📦 Installing prerequisites...${RESET}"
./install_prerequisites.sh

# -----------------------------------------------------------------------------
# 2. Load all variables 
# -----------------------------------------------------------------------------
CONFIG_FILE="../simulator/data/config.yaml"
[[ ! -f $CONFIG_FILE ]] && { echo "❌ $CONFIG_FILE not found."; exit 1; }

echo -e "${COLOR}[2/8] 📦 Load configuration...${RESET}"
source ./load_config.sh $CONFIG_FILE

echo -e "\n🔧 Loaded configuration from $CONFIG_FILE:"
echo "member1: $MEMBER1_NODES nodes, ${MEMBER1_CPU} CPU, ${MEMBER1_MEM} RAM"
echo "member2: $MEMBER2_NODES nodes, ${MEMBER2_CPU} CPU, ${MEMBER2_MEM} RAM, autoscaler=$MEMBER2_AUTOSCALER"
echo ""

# -----------------------------------------------------------------------------
# 3. Provision infrastructure
# -----------------------------------------------------------------------------
echo -e "${COLOR}[3/8] 📝 Generating configuration files...${RESET}"
./generate_manifests.sh

echo -e "${COLOR}[4/8] ☸️  Bringing up Karmada...${RESET}"
./install_karmada.sh
export KUBECONFIG=~/.kube/karmada.config

# -----------------------------------------------------------------------------
# 4. Setup according to execution mode (before Prometheus for Real mode)
# -----------------------------------------------------------------------------
export KUBECONFIG=~/.kube/members.config

if [[ "$EXECUTION_MODE" == "kwok" ]]; then
    echo -e "${COLOR}[5/8] 🎭 Setting up KWOK mode (simulated)...${RESET}"
    ./kwok-mode_setup.sh
    
    echo -e "${COLOR}[6/8] 📊 Installing Prometheus...${RESET}"
    ./install_prometheus.sh  # includes readiness check and port-forwards
elif [[ "$EXECUTION_MODE" == "real" ]]; then
    echo -e "${COLOR}[5/8] 🌐 Setting up Real mode (creating clusters)...${RESET}"
    ./real-mode_setup.sh
    
    echo -e "${COLOR}[6/8] 📊 Installing Prometheus...${RESET}"
    ./install_prometheus.sh  # includes readiness check and port-forwards
else
    echo -e "${COLOR}❌ Unknown execution mode: ${EXECUTION_MODE}${RESET}"
    echo -e "${COLOR}   Valid options: kwok, real${RESET}"
    exit 1
fi

# Autoscaler (for KWOK mode or KIND mode in member2)
if [[ "${MEMBER2_AUTOSCALER:-true}" == "true" ]]; then
    if [[ "$EXECUTION_MODE" == "kwok" ]]; then
        echo -e "${COLOR}[7/10] ⚙️ Installing Cluster Autoscaler (KWOK)...${RESET}"
        ./install_autoscaler.sh
    elif [[ "$EXECUTION_MODE" == "real" ]]; then
        echo -e "${COLOR}[7/10] ⚙️ Installing Cluster Autoscaler (KIND - member2 only)...${RESET}"
        chmod +x install_autoscaler_kind.sh
        ./install_autoscaler_kind.sh
    fi
else
    echo -e "${COLOR}[7/10] ⚙️ Skipping Autoscaler installation...${RESET}"
fi

echo -e "${COLOR}[8/10] ✅ Mode setup completed${RESET}"

# -----------------------------------------------------------------------------
# 5. Final message
# -----------------------------------------------------------------------------
echo -e "\n${COLOR}[🎉] Environment provisioned successfully!${RESET}"
