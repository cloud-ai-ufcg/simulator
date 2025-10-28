#!/bin/bash
# -----------------------------------------------------------------------------
# Real Mode Setup – prepares environment for real workloads
# -----------------------------------------------------------------------------
# ‣ Behaviour
#   • Creates KIND clusters automatically (if not exist)
#   • Skips KWOK installation
#   • Verifies real cluster connections
#   • Labels nodes appropriately
# -----------------------------------------------------------------------------
COLOR="\033[1;35m"  # Magenta – this script's identity color
RESET="\033[0m"

set -euo pipefail

echo -e "${COLOR}🌐 Real Mode Setup${RESET}"

# 1. Create KIND clusters if they don't exist
echo -e "${COLOR}[1/9] Checking for existing clusters...${RESET}"

# Check if kind is installed
if ! command -v kind &> /dev/null; then
    echo -e "${COLOR}⚠️  kind is not installed. Installing...${RESET}"
    OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
    ARCH="$(uname -m)"
    KIND_VERSION="v0.20.0"
    curl -Lo ./kind https://kind.sigs.k8s.io/dl/${KIND_VERSION}/kind-${OS}-${ARCH}
    chmod +x ./kind
    sudo mv ./kind /usr/local/bin/kind
    echo -e "${COLOR}✅ kind installed${RESET}"
fi

# Check if clusters need to be created or recreated with correct worker count
echo -e "${COLOR}  Checking clusters for worker nodes...${RESET}"
./create_kind_clusters.sh

# 2. Verify clusters are accessible
echo -e "${COLOR}[2/9] Verifying cluster connectivity...${RESET}"

for cluster in member1 member2; do
    # Try with both kind-member1 and member1 context names
    if kubectl config get-contexts -o name | grep -q "^kind-$cluster$"; then
        kubectl config use-context "kind-$cluster" || {
            kubectl config use-context "$cluster" || {
                echo -e "${COLOR}❌ Cannot connect to ${cluster}${RESET}"
                exit 1
            }
        }
    elif kubectl config get-contexts -o name | grep -q "^$cluster$"; then
        kubectl config use-context "$cluster" || {
            echo -e "${COLOR}❌ Cannot connect to ${cluster}${RESET}"
            exit 1
        }
    else
        echo -e "${COLOR}❌ Context '$cluster' not found. Running create_kind_clusters.sh...${RESET}"
        ./create_kind_clusters.sh
    fi
done

echo -e "${COLOR}  ✅ All clusters accessible${RESET}"

# 3. Label nodes (create_real_nodes.sh will handle KIND nodes)
echo -e "${COLOR}[3/9] Labeling nodes...${RESET}"
./create_real_nodes.sh

# 4. Get Docker network IPs for member clusters first
echo -e "${COLOR}[4/9] Getting cluster IPs...${RESET}"
MEMBER1_IP=$(docker inspect member1-control-plane 2>/dev/null | jq -r '.[0].NetworkSettings.Networks.kind.IPAddress' 2>/dev/null || echo "")
MEMBER2_IP=$(docker inspect member2-control-plane 2>/dev/null | jq -r '.[0].NetworkSettings.Networks.kind.IPAddress' 2>/dev/null || echo "")

if [ -z "$MEMBER1_IP" ] || [ "$MEMBER1_IP" = "" ]; then
    echo -e "${COLOR}⚠️  Could not get member1 IP${RESET}"
    exit 1
fi

if [ -z "$MEMBER2_IP" ] || [ "$MEMBER2_IP" = "" ]; then
    echo -e "${COLOR}⚠️  Could not get member2 IP${RESET}"
    exit 1
fi

echo -e "${COLOR}  Member1 IP: ${MEMBER1_IP}${RESET}"
echo -e "${COLOR}  Member2 IP: ${MEMBER2_IP}${RESET}"

# 5. Update members.config with Docker network IPs
echo -e "${COLOR}[5/9] Updating members.config with Docker IPs...${RESET}"
if [ -f "update_members_kubeconfig.sh" ]; then
    chmod +x update_members_kubeconfig.sh
    ./update_members_kubeconfig.sh
else
    echo -e "${COLOR}  ⚠️  update_members_kubeconfig.sh not found, skipping${RESET}"
fi

# 6. Switch to Karmada config and register/update clusters
echo -e "${COLOR}[6/9] Checking and registering clusters...${RESET}"
export KUBECONFIG=~/.kube/karmada.config 2>/dev/null || export KUBECONFIG=~/.kube/config
kubectl config use-context karmada-apiserver

# Check if karmadactl is available
GOPATH=$(go env GOPATH | awk -F ':' '{print $1}')
KARMADACTL_BIN="${GOPATH}/bin/karmadactl"

# Always delete existing clusters to ensure fresh registration with correct IPs
echo -e "${COLOR}  Cleaning up existing cluster registrations...${RESET}"
kubectl delete cluster member1 2>/dev/null || true
kubectl delete cluster member2 2>/dev/null || true
sleep 2

# Register clusters fresh with correct members.config
echo -e "${COLOR}  Registering clusters with correct IPs...${RESET}"
for cluster in member1 member2; do
    echo -e "${COLOR}  Registering $cluster to Karmada...${RESET}"
    if [ -f "$KARMADACTL_BIN" ]; then
        ${KARMADACTL_BIN} join $cluster \
            --karmada-context=karmada-apiserver \
            --cluster-kubeconfig=$HOME/.kube/members.config \
            --cluster-context=$cluster || echo -e "${COLOR}  Warning: Registration may have failed, will retry...${RESET}"
    fi
done

# Wait for clusters to be registered
echo -e "${COLOR}  Waiting for clusters to appear...${RESET}"
sleep 5

# 7. Update endpoints and TLS configuration to ensure Docker network IPs  
echo -e "${COLOR}[7/9] Ensuring cluster endpoints and TLS configuration...${RESET}"

# Force update endpoints to ensure they're correct (in case registration picked wrong ones)
echo -e "${COLOR}  Setting member1 endpoint to https://${MEMBER1_IP}:6443${RESET}"
kubectl patch cluster member1 --type='merge' -p="{\"spec\":{\"apiEndpoint\":\"https://${MEMBER1_IP}:6443\",\"insecureSkipTLSVerification\":true}}"

echo -e "${COLOR}  Setting member2 endpoint to https://${MEMBER2_IP}:6443${RESET}"
kubectl patch cluster member2 --type='merge' -p="{\"spec\":{\"apiEndpoint\":\"https://${MEMBER2_IP}:6443\",\"insecureSkipTLSVerification\":true}}"

# Wait a bit for endpoints to be processed
sleep 3

# Label clusters
echo -e "${COLOR}  Labeling clusters...${RESET}"
kubectl label cluster member1 cloud=private --overwrite 2>/dev/null || true
kubectl label cluster member2 cloud=public --overwrite 2>/dev/null || true

# Wait for clusters to be ready
echo -e "${COLOR}[8/9] Waiting for clusters to be ready...${RESET}"
for i in {1..60}; do
    MEMBER1_READY=$(kubectl get cluster member1 -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "False")
    MEMBER2_READY=$(kubectl get cluster member2 -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "False")
    
    if [ "$MEMBER1_READY" = "True" ] && [ "$MEMBER2_READY" = "True" ]; then
        echo -e "${COLOR}✅ Clusters are ready${RESET}"
        break
    fi
    
    if [ $i -eq 60 ]; then
        echo -e "${COLOR}⚠️  Clusters not ready after 3 minutes${RESET}"
    fi
    
    sleep 3
done

# 9. Apply propagation policies
echo -e "${COLOR}[9/9] Applying Karmada policies...${RESET}"
if ! kubectl get clusterpropagationpolicy deploy-private >/dev/null 2>&1; then
    if [ -f "clusterpropagationpolicy.yaml" ]; then
        kubectl apply -f clusterpropagationpolicy.yaml
    fi
fi

echo -e "${COLOR}✅ Real mode setup completed!${RESET}"
