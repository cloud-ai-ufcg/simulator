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
echo -e "${COLOR}[1/5] Generating KWOK provider templates...${RESET}"

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
echo -e "${COLOR}[2/5] Generating ClusterPropagationPolicy...${RESET}"

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
    spreadConstraints:
      - spreadByField: "cluster"
        minGroups: 1
        maxGroups: 1
EOF

echo -e "${COLOR}[✓] clusterpropagationpolicy.yaml generated.${RESET}"

# -----------------------------------------------------------------------------
# 3. Generate KWOK autoscaler configuration
# -----------------------------------------------------------------------------
echo -e "${COLOR}[3/5] Generating kwok-provider-config.yaml...${RESET}"

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
# 4. Generate Stage configuration for KWOK
# -----------------------------------------------------------------------------
echo -e "${COLOR}[4/5] Generating fast-stages.yaml...${RESET}"

cat > fast-stages.yaml <<'EOF'
apiVersion: kwok.x-k8s.io/v1alpha1
kind: Stage
metadata:
  name: pod-ready
spec:
  resourceRef:
    apiGroup: v1
    kind: Pod
  selector:
    matchExpressions:
    - key: '.metadata.deletionTimestamp'
      operator: 'DoesNotExist'
    - key: '.status.podIP'
      operator: 'DoesNotExist'
  delay:
    durationMilliseconds: 1000
    durationFrom:
      expressionFrom: '.metadata.annotations["pod-ready.stage.kwok.x-k8s.io/delay"]'
    # jitterDurationMilliseconds: 10000
    jitterDurationFrom:
      expressionFrom: '.metadata.annotations["pod-ready.stage.kwok.x-k8s.io/jitter-delay"]'
  next:
    statusTemplate: |
      {{ $now := Now }}

      conditions:
      - lastTransitionTime: {{ $now | Quote }}
        status: "True"
        type: Initialized
      - lastTransitionTime: {{ $now | Quote }}
        status: "True"
        type: Ready
      - lastTransitionTime: {{ $now | Quote }}
        status: "True"
        type: ContainersReady
      {{ range .spec.readinessGates }}
      - lastTransitionTime: {{ $now | Quote }}
        status: "True"
        type: {{ .conditionType | Quote }}
      {{ end }}

      containerStatuses:
      {{ range .spec.containers }}
      - image: {{ .image | Quote }}
        name: {{ .name | Quote }}
        ready: true
        restartCount: 0
        state:
          running:
            startedAt: {{ $now | Quote }}
      {{ end }}

      initContainerStatuses:
      {{ range .spec.initContainers }}
      - image: {{ .image | Quote }}
        name: {{ .name | Quote }}
        ready: true
        restartCount: 0
        {{ if eq .restartPolicy "Always" }}
        started: true
        state:
          running:
            startedAt: {{ $now | Quote }}
        {{ else }}
        state:
          terminated:
            exitCode: 0
            finishedAt: {{ $now | Quote }}
            reason: Completed
            startedAt: {{ $now | Quote }}
        {{ end }}
      {{ end }}

      hostIP: {{ NodeIPWith .spec.nodeName | Quote }}
      podIP: {{ PodIPWith .spec.nodeName ( or .spec.hostNetwork false ) ( or .metadata.uid "" ) ( or .metadata.name "" ) ( or .metadata.namespace "" ) | Quote }}
      phase: Running
      startTime: {{ $now | Quote }}
---
apiVersion: kwok.x-k8s.io/v1alpha1
kind: Stage
metadata:
  name: pod-complete
spec:
  resourceRef:
    apiGroup: v1
    kind: Pod
  selector:
    matchExpressions:
    - key: '.metadata.deletionTimestamp'
      operator: 'DoesNotExist'
    - key: '.status.phase'
      operator: 'In'
      values:
      - 'Running'
    - key: '.metadata.ownerReferences.[].kind'
      operator: 'In'
      values:
      - 'Job'
  delay:
    durationMilliseconds: 1000
    durationFrom:
      expressionFrom: '.metadata.annotations["pod-complete.stage.kwok.x-k8s.io/delay"]'
    # jitterDurationMilliseconds: 10000
    jitterDurationFrom:
      expressionFrom: '.metadata.annotations["pod-complete.stage.kwok.x-k8s.io/jitter-delay"]'
  next:
    statusTemplate: |
      {{ $now := Now }}
      {{ $root := . }}
      containerStatuses:
      {{ range $index, $item := .spec.containers }}
      {{ $origin := index $root.status.containerStatuses $index }}
      - image: {{ $item.image | Quote }}
        name: {{ $item.name | Quote }}
        ready: false
        restartCount: 0
        started: false
        state:
          terminated:
            exitCode: 0
            finishedAt: {{ $now | Quote }}
            reason: Completed
            startedAt: {{ $now | Quote }}
      {{ end }}
      phase: Succeeded
---
apiVersion: kwok.x-k8s.io/v1alpha1
kind: Stage
metadata:
  name: pod-delete
spec:
  resourceRef:
    apiGroup: v1
    kind: Pod
  selector:
    matchExpressions:
    - key: '.metadata.deletionTimestamp'
      operator: 'Exists'
  delay:
    durationMilliseconds: 1000
    durationFrom:
      expressionFrom: '.metadata.annotations["pod-delete.stage.kwok.x-k8s.io/delay"]'
    jitterDurationFrom:
      expressionFrom: '.metadata.deletionTimestamp'
  next:
    finalizers:
      empty: true
    delete: true
---
apiVersion: kwok.x-k8s.io/v1alpha1
kind: Stage
metadata:
  name: node-initialize
spec:
  resourceRef:
    apiGroup: v1
    kind: Node
  selector:
    matchExpressions:
    - key: '.status.conditions.[] | select( .type == "Ready" ) | .status'
      operator: 'NotIn'
      values:
      - 'True'
  next:
    statusTemplate: |
      {{ $now := Now }}
      {{ $lastTransitionTime := or .metadata.creationTimestamp $now }}
      conditions:
      {{ range NodeConditions }}
      - lastHeartbeatTime: {{ $now | Quote }}
        lastTransitionTime: {{ $lastTransitionTime | Quote }}
        message: {{ .message | Quote }}
        reason: {{ .reason | Quote }}
        status: {{ .status | Quote }}
        type: {{ .type  | Quote}}
      {{ end }}

      addresses:
      {{ with .status.addresses }}
      {{ YAML . 1 }}
      {{ else }}
      {{ with NodeIP }}
      - address: {{ . | Quote }}
        type: InternalIP
      {{ end }}
      {{ with NodeName }}
      - address: {{ . | Quote }}
        type: Hostname
      {{ end }}
      {{ end }}

      {{ with NodePort }}
      daemonEndpoints:
        kubeletEndpoint:
          Port: {{ . }}
      {{ end }}

      allocatable:
      {{ with .status.allocatable }}
      {{ YAML . 1 }}
      {{ else }}
        cpu: 1k
        memory: 1Ti
        pods: 1M
      {{ end }}
      capacity:
      {{ with .status.capacity }}
      {{ YAML . 1 }}
      {{ else }}
        cpu: 1k
        memory: 1Ti
        pods: 1M
      {{ end }}

      {{ $nodeInfo := .status.nodeInfo }}
      {{ $kwokVersion := printf "kwok-%s" Version }}
      nodeInfo:
        architecture: {{ or $nodeInfo.architecture "amd64" }}
        bootID: {{ or $nodeInfo.bootID `""` }}
        containerRuntimeVersion: {{ or $nodeInfo.containerRuntimeVersion $kwokVersion }}
        kernelVersion: {{ or $nodeInfo.kernelVersion $kwokVersion }}
        kubeProxyVersion: {{ or $nodeInfo.kubeProxyVersion $kwokVersion }}
        kubeletVersion: {{ or $nodeInfo.kubeletVersion $kwokVersion }}
        machineID: {{ or $nodeInfo.machineID `""` }}
        operatingSystem: {{ or $nodeInfo.operatingSystem "linux" }}
        osImage: {{ or $nodeInfo.osImage `""` }}
        systemUUID: {{ or $nodeInfo.systemUUID `""` }}
      phase: Running
---
apiVersion: kwok.x-k8s.io/v1alpha1
kind: Stage
metadata:
  name: node-heartbeat-with-lease
spec:
  resourceRef:
    apiGroup: v1
    kind: Node
  selector:
    matchExpressions:
    - key: '.status.phase'
      operator: 'In'
      values:
      - 'Running'
    - key: '.status.conditions.[] | select( .type == "Ready" ) | .status'
      operator: 'In'
      values:
      - 'True'
  delay:
    durationMilliseconds: 600000
    jitterDurationMilliseconds: 610000
  next:
    statusTemplate: |
      {{ $now := Now }}
      {{ $lastTransitionTime := or .metadata.creationTimestamp $now }}
      conditions:
      {{ range NodeConditions }}
      - lastHeartbeatTime: {{ $now | Quote }}
        lastTransitionTime: {{ $lastTransitionTime | Quote }}
        message: {{ .message | Quote }}
        reason: {{ .reason | Quote }}
        status: {{ .status | Quote }}
        type: {{ .type | Quote }}
      {{ end }}

      addresses:
      {{ with .status.addresses }}
      {{ YAML . 1 }}
      {{ else }}
      {{ with NodeIP }}
      - address: {{ . | Quote }}
        type: InternalIP
      {{ end }}
      {{ with NodeName }}
      - address: {{ . | Quote }}
        type: Hostname
      {{ end }}
      {{ end }}

      {{ with NodePort }}
      daemonEndpoints:
        kubeletEndpoint:
          Port: {{ . }}
      {{ end }}
EOF

echo -e "${COLOR}[✓] fast-stages.yaml generated.${RESET}"

# -----------------------------------------------------------------------------
# 5. Summary of output files
# -----------------------------------------------------------------------------
echo
echo -e "${COLOR}[5/5] Generated files:${RESET}"
ls -1 \
  kwok-provider-templates-member1.yaml \
  kwok-provider-templates-member2.yaml \
  clusterpropagationpolicy.yaml \
  kwok-provider-config.yaml \
  fast-stages.yaml