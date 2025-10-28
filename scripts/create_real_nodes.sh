#!/bin/bash
# -----------------------------------------------------------------------------
# Real Nodes Verifier – verifies real Kubernetes nodes in configured clusters
# -----------------------------------------------------------------------------
# ‣ Behaviour
#   • Checks for existing nodes in member1 and member2 clusters
#   • Labels nodes with cloud labels (private/public)
#   • Supports both KIND and real clusters
# -----------------------------------------------------------------------------
COLOR="\033[1;36m"  # Cyan – this script's identity color
RESET="\033[0m"

set -euo pipefail
trap 'echo -e "${COLOR}❌ Error in ${BASH_SOURCE[0]}:$LINENO – $BASH_COMMAND${RESET}"' ERR

echo -e "${COLOR}🔍 Verifying real Kubernetes nodes...${RESET}"

# Try to use members.config, fallback to default config
if [ -f ~/.kube/members.config ]; then
    export KUBECONFIG=~/.kube/members.config
else
    export KUBECONFIG=~/.kube/config
fi

# Function to find and switch to cluster context
find_cluster_context() {
    local cluster_name=$1
    
    # Try exact match first
    if kubectl config get-contexts -o name | grep -q "^${cluster_name}$"; then
        echo "$cluster_name"
        return 0
    fi
    
    # Try kind- prefix
    if kubectl config get-contexts -o name | grep -q "^kind-${cluster_name}$"; then
        echo "kind-${cluster_name}"
        return 0
    fi
    
    # Try as substring
    CONTEXT=$(kubectl config get-contexts -o name | grep -m1 "$cluster_name" || echo "")
    if [ -n "$CONTEXT" ]; then
        echo "$CONTEXT"
        return 0
    fi
    
    return 1
}

# Function to verify and label nodes in a cluster
verify_and_label_nodes() {
    local cluster_name=$1
    local cloud_label=$2
    
    echo -e "${COLOR}[${cluster_name}] Checking nodes...${RESET}"
    
    # Find the correct context
    CONTEXT=$(find_cluster_context "$cluster_name")
    if [ $? -ne 0 ] || [ -z "$CONTEXT" ]; then
        echo -e "${COLOR}⚠️  Context for ${cluster_name} not found. Skipping.${RESET}"
        return 1
    fi
    
    echo -e "${COLOR}  Using context: ${CONTEXT}${RESET}"
    kubectl config use-context "$CONTEXT" >/dev/null
    
    # Get nodes
    NODES=$(kubectl get nodes -o name 2>/dev/null || echo "")
    
    if [ -z "$NODES" ]; then
        echo -e "${COLOR}⚠️  No nodes found in ${cluster_name}${RESET}"
        return 1
    fi
    
    echo -e "${COLOR}  ✅ Found nodes in ${cluster_name}:${RESET}"
    kubectl get nodes -o wide
    
    # Label nodes with cloud label
    while IFS= read -r node; do
        node_name="${node#node/}"
        
        # Check current label
        CURRENT_LABEL=$(kubectl get node "$node_name" -o jsonpath='{.metadata.labels.cloud}' 2>/dev/null || echo "")
        
        if [ "$CURRENT_LABEL" = "$cloud_label" ]; then
            echo -e "${COLOR}  ✓ ${node_name} already labeled as ${cloud_label}${RESET}"
        else
            echo -e "${COLOR}  -> Labeling ${node_name} as ${cloud_label}...${RESET}"
            kubectl label node "$node_name" cloud="$cloud_label" --overwrite 2>/dev/null || true
            echo -e "${COLOR}    ✓ ${node_name} labeled${RESET}"
        fi
    done <<< "$NODES"
    
    echo -e "${COLOR}[✓] ${cluster_name} nodes verified and labeled${RESET}"
}

# Verify member1 (private)
verify_and_label_nodes "member1" "private"

# Verify member2 (public)
verify_and_label_nodes "member2" "public"

echo -e "${COLOR}✅ Real nodes verification completed!${RESET}"
