#!/bin/bash

# Script para criar clusters KIND para modo Real
# Cria clusters reais usando KIND ao invés de KWOK

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}==============================${NC}"
echo -e "${BLUE}  Create KIND Clusters (Real Mode)${NC}"
echo -e "${BLUE}==============================${NC}"
echo ""

# Check if kind is installed
if ! command -v kind &> /dev/null; then
    echo -e "${RED}❌ kind is not installed${NC}"
    echo -e "${YELLOW}Installing kind...${NC}"
    
    # Detect OS
    OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
    ARCH="$(uname -m)"
    
    # Download kind
    KIND_VERSION="v0.20.0"
    curl -Lo ./kind https://kind.sigs.k8s.io/dl/${KIND_VERSION}/kind-${OS}-${ARCH}
    chmod +x ./kind
    sudo mv ./kind /usr/local/bin/kind
fi

echo -e "${GREEN}✅ kind is installed: $(kind --version)${NC}"
echo ""

# Read node count from config.yaml
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/../simulator/data/config.yaml"
if [ ! -f "$CONFIG_FILE" ]; then
    echo -e "${RED}❌ Config file not found: $CONFIG_FILE${NC}"
    exit 1
fi

# Parse node counts from config.yaml
MEMBER1_NODES=$(grep -A 4 "member1:" "$CONFIG_FILE" | grep "nodes:" | awk '{print $2}')
MEMBER2_NODES=$(grep -A 4 "member2:" "$CONFIG_FILE" | grep "nodes:" | awk '{print $2}')

# Default to 3 workers if not found
MEMBER1_WORKERS=${MEMBER1_NODES:-3}
MEMBER2_WORKERS=${MEMBER2_NODES:-3}

echo -e "${BLUE}📋 Configuration from config.yaml:${NC}"
echo -e "   Member1: 1 control-plane + ${MEMBER1_WORKERS} workers = $((1 + MEMBER1_WORKERS)) total nodes"
echo -e "   Member2: 1 control-plane + ${MEMBER2_WORKERS} workers = $((1 + MEMBER2_WORKERS)) total nodes"
echo ""

# Clean up any orphaned Docker containers
echo -e "${YELLOW}🧹 Cleaning up orphaned containers...${NC}"
docker rm -f $(docker ps -aq -f "name=member") 2>/dev/null || true

# Check if clusters already exist
if kind get clusters | grep -q "member1"; then
    echo -e "${GREEN}✓ Cluster 'member1' already exists${NC}"
    MEMBER1_NEEDS_CREATE=false
else
    echo -e "${YELLOW}  Cluster 'member1' does not exist - will create with Karmada config${NC}"
    MEMBER1_NEEDS_CREATE=true
fi

if kind get clusters | grep -q "member2"; then
    echo -e "${GREEN}✓ Cluster 'member2' already exists${NC}"
    MEMBER2_NEEDS_CREATE=false
else
    echo -e "${YELLOW}  Cluster 'member2' does not exist - will create with Karmada config${NC}"
    MEMBER2_NEEDS_CREATE=true
fi

echo ""

# Create member1 cluster using Karmada config
if [ "$MEMBER1_NEEDS_CREATE" = true ]; then
    echo -e "${BLUE}[1/2] Creating member1 cluster (private) with ${MEMBER1_WORKERS} workers...${NC}"

    # Check if Karmada config exists, if so, use it (it already has workers now)
    KARMADA_CONFIG="$SCRIPT_DIR/../karmada/artifacts/kindClusterConfig/member1.yaml"
    if [ -f "$KARMADA_CONFIG" ]; then
        echo -e "${BLUE}  Using Karmada config (already includes workers)...${NC}"
        kind create cluster --name member1 --config "$KARMADA_CONFIG"
    else
        # Generate KIND config with dynamic worker count
        cat > /tmp/member1-kind-config.yaml <<EOF
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
  - role: control-plane
    kubeadmConfigPatches:
      - |
        kind: InitConfiguration
        nodeRegistration:
          kubeletExtraArgs:
            node-labels: "cloud=private"
EOF

        # Add workers dynamically
        for i in $(seq 1 ${MEMBER1_WORKERS}); do
            cat >> /tmp/member1-kind-config.yaml <<EOF
  - role: worker
    kubeadmConfigPatches:
      - |
        kind: JoinConfiguration
        nodeRegistration:
          kubeletExtraArgs:
            node-labels: "cloud=private"
EOF
        done

        kind create cluster --name member1 --config /tmp/member1-kind-config.yaml
        rm /tmp/member1-kind-config.yaml
    fi

    # Merge member1 kubeconfig - only if context doesn't exist
    kind export kubeconfig --name member1
    if kubectl config get-contexts | grep -q " member1 "; then
        # Context already exists, just update cluster
        echo -e "${BLUE}  Context 'member1' already exists, skipping rename${NC}"
    else
        kubectl config rename-context kind-member1 member1 || true
    fi

    echo -e "${GREEN}✅ member1 cluster created${NC}"
else
    echo -e "${BLUE}[1/2] Skipping member1 - already exists with correct number of workers${NC}"
fi

# Create member2 cluster (public) with workers - only if needed
if [ "$MEMBER2_NEEDS_CREATE" = true ]; then
    echo -e "${BLUE}[2/2] Creating member2 cluster (public) with ${MEMBER2_WORKERS} workers...${NC}"

    # Check if Karmada config exists, if so, use it (it already has workers now)
    KARMADA_CONFIG="$SCRIPT_DIR/../karmada/artifacts/kindClusterConfig/member2.yaml"
    if [ -f "$KARMADA_CONFIG" ]; then
        echo -e "${BLUE}  Using Karmada config (already includes workers)...${NC}"
        kind create cluster --name member2 --config "$KARMADA_CONFIG"
    else
        # Generate KIND config with dynamic worker count
        cat > /tmp/member2-kind-config.yaml <<EOF
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
  - role: control-plane
    kubeadmConfigPatches:
      - |
        kind: InitConfiguration
        nodeRegistration:
          kubeletExtraArgs:
            node-labels: "cloud=public"
EOF

        # Add workers dynamically
        for i in $(seq 1 ${MEMBER2_WORKERS}); do
            cat >> /tmp/member2-kind-config.yaml <<EOF
  - role: worker
    kubeadmConfigPatches:
      - |
        kind: JoinConfiguration
        nodeRegistration:
          kubeletExtraArgs:
            node-labels: "cloud=public"
EOF
        done

        kind create cluster --name member2 --config /tmp/member2-kind-config.yaml
        rm /tmp/member2-kind-config.yaml
    fi

    # Merge member2 kubeconfig - only if context doesn't exist
    kind export kubeconfig --name member2
    if kubectl config get-contexts | grep -q " member2 "; then
        # Context already exists, just update cluster
        echo -e "${BLUE}  Context 'member2' already exists, skipping rename${NC}"
    else
        kubectl config rename-context kind-member2 member2 || true
    fi

    echo -e "${GREEN}✅ member2 cluster created${NC}"
else
    echo -e "${BLUE}[2/2] Skipping member2 - already exists with correct number of workers${NC}"
fi

echo ""
echo -e "${GREEN}==============================${NC}"
echo -e "${GREEN}  Summary${NC}"
echo -e "${GREEN}==============================${NC}"
echo ""
echo -e "${GREEN}✅ Created clusters:${NC}"
kind get clusters

echo ""
echo -e "${BLUE}ℹ️  Note: If clusters were recreated, you may need to reconnect them:${NC}"
echo -e "${YELLOW}   Run: make setup-kubernetes-infra${NC}"
echo -e "${YELLOW}   This will reconnect the clusters to Karmada and reinstall Prometheus${NC}"

echo ""
echo -e "${BLUE}To verify:${NC}"
echo "  kubectl --context member1 get nodes"
echo "  kubectl --context member2 get nodes"
echo ""
