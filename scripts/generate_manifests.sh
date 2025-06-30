#!/bin/bash
# -----------------------------------------------------------------------------
# Manifest Generator – produces KWOK templates, Karmada propagation policies,
# and Autoscaler configMaps based on environment parameters from main.sh.
# -----------------------------------------------------------------------------
# ‣ Behaviour
#   • Generates one KWOK node template per cluster (member1, member2).
#   • Produces Karmada ClusterPropagationPolicies for public/private workloads.
#   • Outputs KWOK provider configuration used by the autoscaler.
# -----------------------------------------------------------------------------
#   Colour palette
# -----------------------------------------------------------------------------
COLOR="\033[1;32m"  # Green – this script's identity color
RESET="\033[0m"

set -euo pipefail
trap 'echo -e "${COLOR}❌  Error in ${BASH_SOURCE[0]}:$LINENO – $BASH_COMMAND${RESET}"' ERR

# -----------------------------------------------------------------------------
# 1. Generate KWOK node templates
# -----------------------------------------------------------------------------
echo -e "${COLOR}[1/4] Generating KWOK provider templates...${RESET}"

generate_kwok_template() {
  local CLUSTER=$1
  local CPU=$2
  local MEMORY=$3
  local FILE="kwok-provider-templates-${CLUSTER}.yaml"
  local CLUSTER_TYPE=""

  if [[ "$CLUSTER" == "member1" ]]; then
    CLUSTER_TYPE="private"
  elif [[ "$CLUSTER" == "member2" ]]; then
    CLUSTER_TYPE="public"
  fi

  # Write YAML template to file using here-document
  cat > "$FILE" <<EOF_KWOK_TEMPLATE
apiVersion: v1
kind: ConfigMap
metadata:
  name: kwok-provider-templates
  namespace: default
data:
  nodes: |-
    - name: ${CLUSTER}-template
      status: "Ready"
      resources:
        cpu: "${CPU}"
        memory: "${MEMORY}"
      labels:
        cloud: ${CLUSTER_TYPE}
        kwok.x-k8s.io/node: fake
      taints:
        - effect: NoSchedule
          key: kwok-provider
          value: "true"
EOF_KWOK_TEMPLATE

  echo -e "${COLOR}[✓] $FILE generated for ${CLUSTER} with template @ ${CPU} CPU / ${MEMORY}${RESET}"
}

# Generate template for member1 (private cloud)
generate_kwok_template "member1" "$MEMBER1_CPU" "$MEMBER1_MEM"

# Generate template for member2 (public cloud)
generate_kwok_template "member2" "$MEMBER2_CPU" "$MEMBER2_MEM"

# -----------------------------------------------------------------------------
# 2. Generate Karmada ClusterPropagationPolicies
# -----------------------------------------------------------------------------
echo -e "${COLOR}[2/4] Generating ClusterPropagationPolicy...${RESET}"

cat > clusterpropagationpolicy.yaml <<EOF
apiVersion: policy.karmada.io/v1alpha1
kind: ClusterPropagationPolicy
metadata:
  name: deploy-private
spec:
  resourceSelectors:
    - apiVersion: apps/v1
      kind: Deployment
      namespace: default
      labelSelector:
        matchLabels:
          cloud: private
    - apiVersion: batch/v1
      kind: Job
      namespace: default
      labelSelector:
        matchLabels:
          cloud: private
  placement:
    clusterAffinity:
      labelSelector:
        matchLabels:
          cloud: private
    replicaScheduling:
      replicaSchedulingType: Divided
      replicaDivisionPreference: Weighted
      weightPreference:
        staticWeightList:
          - targetCluster:
              clusterNames: [member1]
            weight: 100
---
apiVersion: policy.karmada.io/v1alpha1
kind: ClusterPropagationPolicy
metadata:
  name: deploy-public
spec:
  resourceSelectors:
    - apiVersion: apps/v1
      kind: Deployment
      namespace: default
      labelSelector:
        matchLabels:
          cloud: public
    - apiVersion: batch/v1
      kind: Job
      namespace: default
      labelSelector:
        matchLabels:
          cloud: public
  placement:
    clusterAffinity:
      labelSelector:
        matchLabels:
          cloud: public
    replicaScheduling:
      replicaSchedulingType: Divided
      replicaDivisionPreference: Weighted
      weightPreference:
        staticWeightList:
          - targetCluster:
              clusterNames: [member2]
            weight: 100
---
apiVersion: policy.karmada.io/v1alpha1
kind: ClusterPropagationPolicy
metadata:
  name: deploy-default
spec:
  resourceSelectors:
    - apiVersion: apps/v1
      kind: Deployment
      namespace: default
      labelSelector:
        matchExpressions:
          - key: cloud
            operator: DoesNotExist
    - apiVersion: batch/v1
      kind: Job
      namespace: default
      labelSelector:
        matchExpressions:
          - key: cloud
            operator: DoesNotExist
  placement:
    clusterAffinity:
      labelSelector: {}
    replicaScheduling:
      replicaSchedulingType: Divided
      replicaDivisionPreference: Weighted
EOF

echo -e "${COLOR}[✓] clusterpropagationpolicy.yaml generated.${RESET}"

# -----------------------------------------------------------------------------
# 3. Generate KWOK autoscaler configuration
# -----------------------------------------------------------------------------
echo -e "${COLOR}[3/4] Generating kwok-provider-config.yaml...${RESET}"

cat > kwok-provider-config.yaml <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: kwok-provider-config
  namespace: default
  labels:
    app.kubernetes.io/managed-by: Helm
  annotations:
    meta.helm.sh/release-name: autoscaler-kwok
    meta.helm.sh/release-namespace: default
data:
  config.yaml: |
    apiVersion: config.kwok.x-k8s.io/v1alpha1
    kind: KwokConfiguration
    readNodesFrom: configmap
    nodeGroups:
      - name: fake-nodegroup
        fromNodeLabelKey: kwok.x-k8s.io/node
        minSize: 0
        maxSize: 100
EOF

echo -e "${COLOR}[✓] kwok-provider-config.yaml generated.${RESET}"

# -----------------------------------------------------------------------------
# 4. Summary of output files
# -----------------------------------------------------------------------------
echo
echo -e "${COLOR}[4/4] Generated files:${RESET}"
ls -1 \
  kwok-provider-templates-member1.yaml \
  kwok-provider-templates-member2.yaml \
  clusterpropagationpolicy.yaml \
  kwok-provider-config.yaml