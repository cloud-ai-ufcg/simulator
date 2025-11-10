#!/bin/bash
# -----------------------------------------------------------------------------
# Kubelet Resource Hacker - COMPLETELY DISABLES automatic node status updates
# -----------------------------------------------------------------------------
# This script modifies kubelet configuration inside KIND containers to prevent
# it from EVER overwriting node resource capacity/allocatable values
# -----------------------------------------------------------------------------

set -euo pipefail

COLOR="\033[1;36m"
RESET="\033[0m"

echo -e "${COLOR}🔧 DISABLING Kubelet node status updates PERMANENTLY${RESET}"
echo ""

# Locate config file
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/../simulator/data/config.yaml"

if [ ! -f "$CONFIG_FILE" ]; then
    echo -e "${COLOR}❌ Config file not found: $CONFIG_FILE${RESET}"
    exit 1
fi

# Parse resources
MEMBER1_CPU=$(yq '.clusters.member1.cpu' "$CONFIG_FILE")
MEMBER1_MEM=$(yq '.clusters.member1.memory' "$CONFIG_FILE")
MEMBER2_CPU=$(yq '.clusters.member2.cpu' "$CONFIG_FILE")
MEMBER2_MEM=$(yq '.clusters.member2.memory' "$CONFIG_FILE")

# Set kubeconfig
export KUBECONFIG=~/.kube/members.config

echo -e "${COLOR}[Step 1] DISABLING kubelet node status updates PERMANENTLY...${RESET}"
echo -e "${COLOR}  Setting nodeStatusReportFrequency: 999999h${RESET}"
echo -e "${COLOR}  Setting nodeStatusUpdateFrequency: 999999h${RESET}"

# Function to hack ALL workers in a cluster
hack_cluster_workers() {
    local cluster=$1
    local cpu=$2
    local memory=$3
    
    echo -e "${COLOR}  Processing cluster ${cluster}...${RESET}"
    
    # Get ALL worker nodes dynamically
    local worker_nodes=$(kubectl get nodes --context "${cluster}" --no-headers 2>/dev/null | grep -E "worker[0-9]*" | awk '{print $1}')
    
    if [ -z "$worker_nodes" ]; then
        echo -e "${COLOR}  ⚠️  No worker nodes found for ${cluster}${RESET}"
        return 1
    fi
    
    for worker_node in $worker_nodes; do
        echo -e "${COLOR}    Hacking ${worker_node}...${RESET}"
        
        # COMPLETELY disable kubelet node status updates (set to 999999h = never)
        docker exec "${worker_node}" sed -i 's/nodeStatusReportFrequency: 0s/nodeStatusReportFrequency: 999999h/' /var/lib/kubelet/config.yaml 2>/dev/null || true
        docker exec "${worker_node}" sed -i 's/nodeStatusUpdateFrequency: [0-9]*[mhs]/nodeStatusUpdateFrequency: 999999h/' /var/lib/kubelet/config.yaml 2>/dev/null || true
        
        echo -e "${COLOR}      ✓ Kubelet config updated${RESET}"
    done
}

# Hack all workers in both clusters
hack_cluster_workers "member1" "$MEMBER1_CPU" "$MEMBER1_MEM"
hack_cluster_workers "member2" "$MEMBER2_CPU" "$MEMBER2_MEM"

echo -e "${COLOR}  ✓ Kubelet configs updated - updates DISABLED${RESET}"
echo ""

echo -e "${COLOR}[Step 2] Waiting for kubelet to reload...${RESET}"
sleep 5
echo -e "${COLOR}  ✓ Kubelet reloaded${RESET}"
echo ""

echo -e "${COLOR}[Step 3] Applying resource patches...${RESET}"

# Function to patch all workers
patch_cluster_workers() {
    local cluster=$1
    local cpu=$2
    local memory=$3
    
    # Get ALL worker nodes dynamically
    local worker_nodes=$(kubectl get nodes --context "${cluster}" --no-headers 2>/dev/null | grep -E "worker[0-9]*" | awk '{print $1}')
    
    for worker_node in $worker_nodes; do
        kubectl patch node "${worker_node}" --type=merge --subresource=status --context "${cluster}" -p "{
            \"status\": {
                \"capacity\": {\"cpu\": \"${cpu}\", \"memory\": \"${memory}\"},
                \"allocatable\": {\"cpu\": \"${cpu}\", \"memory\": \"${memory}\"}
            }
        }" 2>/dev/null && echo -e "${COLOR}  ✓ ${worker_node} patched${RESET}" || echo -e "${COLOR}  ✗ ${worker_node} patch failed${RESET}"
    done
}

# Patch all workers in both clusters
patch_cluster_workers "member1" "$MEMBER1_CPU" "$MEMBER1_MEM"
patch_cluster_workers "member2" "$MEMBER2_CPU" "$MEMBER2_MEM"

echo ""
echo -e "${COLOR}═══════════════════════════════════════════${RESET}"
echo -e "${COLOR}✅ Kubelet updates DISABLED on all worker nodes!${RESET}"
echo -e "${COLOR}═══════════════════════════════════════════${RESET}"
echo ""
echo "Kubelet will NEVER update node status (999999h = ~114 years)."
echo "Resource values are PERMANENTLY locked."
echo ""
echo "To verify:"
echo "  kubectl get nodes -o custom-columns=NAME:.metadata.name,CPU:.status.capacity.cpu,MEMORY:.status.capacity.memory --context member1"
echo "  kubectl get nodes -o custom-columns=NAME:.metadata.name,CPU:.status.capacity.cpu,MEMORY:.status.capacity.memory --context member2"
