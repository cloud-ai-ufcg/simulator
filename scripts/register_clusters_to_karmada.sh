#!/bin/bash
# -----------------------------------------------------------------------------
# Register existing clusters to Karmada - fixes "cluster is not reachable" issue
# -----------------------------------------------------------------------------
COLOR="\033[1;35m"  # Magenta
RESET="\033[0m"

set -euo pipefail

echo -e "${COLOR}🔗 Registering clusters to Karmada...${RESET}"

# Get Karmada config path
export KUBECONFIG=~/.kube/karmada.config
kubectl config use-context karmada-apiserver

# Set variables
MAIN_KUBECONFIG=~/.kube/karmada.config
MEMBER_CLUSTER_KUBECONFIG=~/.kube/members.config
MEMBER_CLUSTER_1_NAME="member1"
MEMBER_CLUSTER_2_NAME="member2"
KARMADA_APISERVER_CLUSTER_NAME="karmada-apiserver"

# Check if karmadactl exists
GOPATH=$(go env GOPATH | awk -F ':' '{print $1}')
KARMADACTL_BIN="${GOPATH}/bin/karmadactl"

if [ ! -f "$KARMADACTL_BIN" ]; then
    echo -e "${COLOR}❌ karmadactl not found. Installing...${RESET}"
    
    # Install karmadactl
    KARMADA_RELEASE=v1.14.1
    GOOS=$(go env GOOS)
    GOARCH=$(go env GOARCH)
    
    if [ ! -d "karmada" ]; then
        git clone --branch $KARMADA_RELEASE --depth 1 https://github.com/karmada-io/karmada.git
    fi
    
    cd karmada && go install ./_cmd/karmadactl && cd ..
    echo -e "${COLOR}✅ karmadactl installed${RESET}"
fi

# Function to check if cluster is ready
check_cluster_ready() {
    local cluster_name=$1
    for i in {1..30}; do
        if kubectl get cluster $cluster_name -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null | grep -q "True"; then
            return 0
        fi
        echo -e "${COLOR}  Waiting for $cluster_name to be ready... (attempt $i)${RESET}"
        sleep 3
    done
    return 1
}

# Check if clusters need to be re-registered
NEED_REGISTER=false

for cluster in member1 member2; do
    if ! check_cluster_ready $cluster; then
        echo -e "${COLOR}⚠️  Cluster $cluster is not ready, will re-register${RESET}"
        NEED_REGISTER=true
    fi
done

if [ "$NEED_REGISTER" = true ]; then
    # Delete existing clusters from Karmada if they exist
    echo -e "${COLOR}[1/3] Cleaning up existing cluster registrations...${RESET}"
    kubectl delete cluster member1 2>/dev/null || true
    kubectl delete cluster member2 2>/dev/null || true
    sleep 2
    
    # Register member1
    echo -e "${COLOR}[2/3] Registering member1 cluster...${RESET}"
    ${KARMADACTL_BIN} join \
        --karmada-context="${KARMADA_APISERVER_CLUSTER_NAME}" \
        ${MEMBER_CLUSTER_1_NAME} \
        --cluster-kubeconfig="${MEMBER_CLUSTER_KUBECONFIG}" \
        --cluster-context="${MEMBER_CLUSTER_1_NAME}" \
        --dry-run 2>&1 || true
    
    ${KARMADACTL_BIN} join \
        --karmada-context="${KARMADA_APISERVER_CLUSTER_NAME}" \
        ${MEMBER_CLUSTER_1_NAME} \
        --cluster-kubeconfig="${MEMBER_CLUSTER_KUBECONFIG}" \
        --cluster-context="${MEMBER_CLUSTER_1_NAME}"
    
    echo -e "${COLOR}[3/3] Registering member2 cluster...${RESET}"
    ${KARMADACTL_BIN} join \
        --karmada-context="${KARMADA_APISERVER_CLUSTER_NAME}" \
        ${MEMBER_CLUSTER_2_NAME} \
        --cluster-kubeconfig="${MEMBER_CLUSTER_KUBECONFIG}" \
        --cluster-context="${MEMBER_CLUSTER_2_NAME}"
    
    # Label clusters
    echo -e "${COLOR}🏷️  Labeling clusters...${RESET}"
    kubectl label cluster member1 cloud=private --overwrite
    kubectl label cluster member2 cloud=public --overwrite
    
    # Wait for clusters to be ready
    echo -e "${COLOR}⏳ Waiting for clusters to be ready...${RESET}"
    sleep 5
    
    for cluster in member1 member2; do
        for i in {1..60}; do
            if kubectl get cluster $cluster -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null | grep -q "True"; then
                echo -e "${COLOR}✅ Cluster $cluster is ready${RESET}"
                break
            fi
            if [ $i -eq 60 ]; then
                echo -e "${COLOR}⚠️  Cluster $cluster is not ready after 3 minutes${RESET}"
            fi
            sleep 3
        done
    done
    
    echo -e "${COLOR}✅ Cluster registration completed!${RESET}"
else
    echo -e "${COLOR}✅ Clusters are already registered and ready${RESET}"
fi

# Show final status
echo -e "\n${COLOR}📊 Cluster Status:${RESET}"
kubectl get clusters

