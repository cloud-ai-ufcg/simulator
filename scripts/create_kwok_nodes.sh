#!/bin/bash
# -----------------------------------------------------------------------------
# KWOK Node Generator – creates fake nodes for member1 and member2 clusters
# using dynamic configuration (CPU, memory, node count) from environment.
# -----------------------------------------------------------------------------
# ‣ Behaviour
#   • Reads config variables exported by main.sh (e.g. MEMBER1_NODES).
#   • Applies YAML manifests directly to simulate nodes.
#   • Adds contextual `cloud` label and KWOK taints for autoscaling simulation.
# -----------------------------------------------------------------------------
#   Colour palette
# -----------------------------------------------------------------------------
COLOR="\033[1;34m"  # Blue – this script's identity color
RESET="\033[0m"

set -euo pipefail
trap 'echo -e "${COLOR}❌  Error in ${BASH_SOURCE[0]}:$LINENO – $BASH_COMMAND${RESET}"' ERR

echo -e "${COLOR}✨ Creating KWOK fake nodes (Initial batch)...${RESET}"

# -----------------------------------------------------------------------------
# Function: create_fake_nodes
# Description: Generates fake KWOK nodes on a given cluster using parameters
#              defined in environment variables (exported by main.sh).
# -----------------------------------------------------------------------------
function create_fake_nodes() {
  local cluster_name=$1
  local num_nodes_var="${cluster_name^^}_NODES"
  local cpu_var="${cluster_name^^}_CPU"
  local mem_var="${cluster_name^^}_MEM"
  local cloud_label=""

  # Assign cloud label based on cluster identity
  cloud_label=$cluster_name

  local NUM_NODES=${!num_nodes_var}
  local CPU=${!cpu_var}
  local MEMORY=${!mem_var}

  echo -e "${COLOR}[${cluster_name}] Creating ${NUM_NODES} initial nodes with ${CPU} CPU and ${MEMORY} RAM...${RESET}"

  export KUBECONFIG=~/.kube/members.config
  kubectl config use-context "$cluster_name"

  for i in $(seq 0 $((NUM_NODES - 1))); do
    NODE_NAME="${cluster_name}-node-${i}"
    echo -e "${COLOR}  -> Creating node: ${NODE_NAME} in ${cluster_name}...${RESET}"
    kubectl apply -f - <<EOF
apiVersion: v1
kind: Node
metadata:
  annotations:
    node.alpha.kubernetes.io/ttl: "0"
    kwok.x-k8s.io/node: fake
  labels:
    beta.kubernetes.io/arch: amd64
    beta.kubernetes.io/os: linux
    kubernetes.io/arch: amd64
    kubernetes.io/hostname: ${NODE_NAME}
    kubernetes.io/os: linux
    kubernetes.io/role: agent
    node-role.kubernetes.io/agent: ""
    type: kwok
    cloud: ${cloud_label}
  name: ${NODE_NAME}
spec:
  taints:
  - effect: NoSchedule
    key: kwok-provider
    value: "true"
status:
  allocatable:
    cpu: ${CPU}
    memory: ${MEMORY}
    pods: 110
  capacity:
    cpu: ${CPU}
    memory: ${MEMORY}
    pods: 110
  nodeInfo:
    architecture: amd64
    bootID: ""
    containerRuntimeVersion: ""
    kernelVersion: ""
    kubeProxyVersion: fake
    kubeletVersion: fake
    machineID: ""
    operatingSystem: linux
    osImage: ""
    systemUUID: ""
  phase: Running
EOF
  done
  echo -e "${COLOR}[✓] Finished creating initial nodes for ${cluster_name}.${RESET}"
}

# -----------------------------------------------------------------------------
# Execute fake node creation for both clusters
# -----------------------------------------------------------------------------
create_fake_nodes "member1"
create_fake_nodes "member2"
create_fake_nodes "member3"

echo -e "${COLOR}✅ All initial KWOK fake nodes created successfully!${RESET}"
