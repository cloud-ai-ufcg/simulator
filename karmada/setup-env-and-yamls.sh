#!/bin/bash

set -e

# Caminho para o script de instalação das ferramentas
INSTALL_SCRIPT="./install-tools.sh"

echo "Executando script de instalação de ferramentas..."
if [ -f "$INSTALL_SCRIPT" ]; then
  bash "$INSTALL_SCRIPT"
else
  echo "Script '$INSTALL_SCRIPT' não encontrado."
  exit 1
fi

echo "Criando clusterpropagationpolicy.yaml..."
cat <<EOF > clusterpropagationpolicy.yaml
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
      labelSelector: {}  # qualquer cluster
    replicaScheduling:
      replicaSchedulingType: Divided
      replicaDivisionPreference: Weighted
EOF

echo "clusterpropagationpolicy.yaml criado."

echo "Criando kwok-provider-config.yaml..."
cat <<EOF > kwok-provider-config.yaml
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

echo "kwok-provider-config.yaml criado."

echo "Criando kwok-provider-templates.yaml..."
cat <<EOF > kwok-provider-templates.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: kwok-provider-templates
  namespace: default
  labels:
    app.kubernetes.io/managed-by: Helm
  annotations:
    meta.helm.sh/release-name: autoscaler-kwok
    meta.helm.sh/release-namespace: default
data:
  templates: |
    apiVersion: v1
    kind: Node
    metadata:
      name: kind-worker-template
      labels:
        type: kwok
        kwok.x-k8s.io/node: fake
        # Este label será usado pelo autoscaler para identificar o nodegroup
        kwok-nodegroup: worker-group
    spec:
      taints:
        - effect: NoSchedule
          key: kwok-provider
          value: true
    status:
      capacity:
        cpu: "12"
        memory: "8Gi"
        pods: "110"
      allocatable:
        cpu: "12"
        memory: "8Gi"
        pods: "110"
      conditions:
        - type: Ready
          status: "True"
          reason: "KubeletReady"
          message: "fake node ready"

  config: |-
    apiVersion: v1alpha1
    readNodesFrom: configmap  # Usando ConfigMap como origem de nós
    nodegroups:
      # Usando o label 'kwok-nodegroup' para identificar o nodegroup
      fromNodeLabelKey: "kwok-nodegroup"
      # Se preferir usar anotação, pode substituir acima e descomentar a linha abaixo
      # fromNodeAnnotation: "example.com/nodegroup"
    configmap:
      name: kwok-provider-templates
EOF

echo "kwok-provider-templates.yaml criado."


echo "Criando general-stages.yaml..."
cat <<EOF > general-stages.yaml
kind: Stage
apiVersion: kwok.x-k8s.io/v1alpha1
metadata:
  name: pod-create
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
  weight: 1
  delay:
    durationMilliseconds: 5000
    durationFrom:
      expressionFrom: '.metadata.annotations["pod-create.stage.kwok.x-k8s.io/delay"]'
    # jitterDurationMilliseconds: 0
    jitterDurationFrom:
      expressionFrom: '.metadata.annotations["pod-create.stage.kwok.x-k8s.io/jitter-delay"]'
  next:
    event:
      type: Normal
      reason: Created
      message: Created container
    finalizers:
      add:
        - value: 'kwok.x-k8s.io/fake'
    statusTemplate: |
      {{ $now := Now }}

      conditions:
      {{ if .spec.initContainers }}
      - lastProbeTime: null
        lastTransitionTime: {{ $now | Quote }}
        message: 'containers with incomplete status: [{{ range .spec.initContainers }} {{ .name }} {{ end }}]'
        reason: ContainersNotInitialized
        status: "False"
        type: Initialized
      {{ else }}
      - lastProbeTime: null
        lastTransitionTime: {{ $now | Quote }}
        status: "True"
        type: Initialized
      {{ end }}
      - lastProbeTime: null
        lastTransitionTime: {{ $now | Quote }}
        message: 'containers with unready status: [{{ range .spec.containers }} {{ .name }} {{ end }}]'
        reason: ContainersNotReady
        status: "False"
        type: Ready
      - lastProbeTime: null
        lastTransitionTime: {{ $now | Quote }}
        message: 'containers with unready status: [{{ range .spec.containers }} {{ .name }} {{ end }}]'
        reason: ContainersNotReady
        status: "False"
        type: ContainersReady
      {{ range .spec.readinessGates }}
      - lastTransitionTime: {{ $now | Quote }}
        status: "True"
        type: {{ .conditionType | Quote }}
      {{ end }}

      {{ if .spec.initContainers }}
      initContainerStatuses:
      {{ range .spec.initContainers }}
      - image: {{ .image | Quote }}
        name: {{ .name | Quote }}
        ready: false
        restartCount: 0
        started: false
        state:
          waiting:
            reason: PodInitializing
      {{ end }}
      containerStatuses:
      {{ range .spec.containers }}
      - image: {{ .image | Quote }}
        name: {{ .name | Quote }}
        ready: false
        restartCount: 0
        started: false
        state:
          waiting:
            reason: PodInitializing
      {{ end }}
      {{ else }}
      containerStatuses:
      {{ range .spec.containers }}
      - image: {{ .image | Quote }}
        name: {{ .name | Quote }}
        ready: false
        restartCount: 0
        started: false
        state:
          waiting:
            reason: ContainerCreating
      {{ end }}
      {{ end }}

      hostIP: {{ NodeIPWith .spec.nodeName | Quote }}
      podIP: {{ PodIPWith .spec.nodeName ( or .spec.hostNetwork false ) ( or .metadata.uid "" ) ( or .metadata.name "" ) ( or .metadata.namespace "" ) | Quote }}
      phase: Pending
---
kind: Stage
apiVersion: kwok.x-k8s.io/v1alpha1
metadata:
  name: pod-init-container-running
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
          - 'Pending'
      - key: '.status.conditions.[] | select( .type == "Initialized" ) | .status'
        operator: 'NotIn'
        values:
          - 'True'
      - key: '.status.initContainerStatuses.[].state.waiting.reason'
        operator: 'Exists'
  weight: 1
  delay:
    durationMilliseconds: 5000
    durationFrom:
      expressionFrom: '.metadata.annotations["pod-init-container-running.stage.kwok.x-k8s.io/delay"]'
    # jitterDurationMilliseconds: 0
    jitterDurationFrom:
      expressionFrom: '.metadata.annotations["pod-init-container-running.stage.kwok.x-k8s.io/jitter-delay"]'
  next:
    statusTemplate: |
      {{ $now := Now }}
      {{ $root := . }}
      initContainerStatuses:
      {{ range $index, $item := .spec.initContainers }}
      {{ $origin := index $root.status.initContainerStatuses $index }}
      - image: {{ $item.image | Quote }}
        name: {{ $item.name | Quote }}
        ready: true
        restartCount: 0
        started: true
        state:
          running:
            startedAt: {{ $now | Quote }}
      {{ end }}
---
kind: Stage
apiVersion: kwok.x-k8s.io/v1alpha1
metadata:
  name: pod-init-container-completed
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
          - 'Pending'
      - key: '.status.initContainerStatuses.[].state.running.startedAt'
        operator: 'Exists'
  weight: 1
  delay:
    durationMilliseconds: 5000
    durationFrom:
      expressionFrom: '.metadata.annotations["pod-init-container-completed.stage.kwok.x-k8s.io/delay"]'
    # jitterDurationMilliseconds: 0
    jitterDurationFrom:
      expressionFrom: '.metadata.annotations["pod-init-container-completed.stage.kwok.x-k8s.io/jitter-delay"]'
  next:
    statusTemplate: |
      {{ $now := Now }}
      {{ $root := . }}
      conditions:
      - lastProbeTime: null
        lastTransitionTime: {{ $now | Quote }}
        status: "True"
        reason: ""
        type: Initialized
      initContainerStatuses:
      {{ range $index, $item := .spec.initContainers }}
      {{ $origin := index $root.status.initContainerStatuses $index }}
      - image: {{ $item.image | Quote }}
        name: {{ $item.name | Quote }}
        ready: true
        restartCount: 0
        started: false
        state:
          terminated:
            exitCode: 0
            finishedAt: {{ $now | Quote }}
            reason: Completed
            startedAt: {{ $now | Quote }}
      {{ end }}
      containerStatuses:
      {{ range .spec.containers }}
      - image: {{ .image | Quote }}
        name: {{ .name | Quote }}
        ready: false
        restartCount: 0
        started: false
        state:
          waiting:
            reason: ContainerCreating
      {{ end }}
---
kind: Stage
apiVersion: kwok.x-k8s.io/v1alpha1
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
      - key: '.status.conditions.[] | select( .type == "Initialized" ) | .status'
        operator: 'In'
        values:
          - 'True'
      - key: '.status.containerStatuses.[].state.running.startedAt'
        operator: 'DoesNotExist'
  weight: 1
  delay:
    durationMilliseconds: 5000
    durationFrom:
      expressionFrom: '.metadata.annotations["pod-ready.stage.kwok.x-k8s.io/delay"]'
    # jitterDurationMilliseconds: 0
    jitterDurationFrom:
      expressionFrom: '.metadata.annotations["pod-ready.stage.kwok.x-k8s.io/jitter-delay"]'
  next:
    delete: false
    statusTemplate: |
      {{ $now := Now }}
      {{ $root := . }}
      conditions:
      - lastProbeTime: null
        lastTransitionTime: {{ $now | Quote }}
        message: ''
        reason: ''
        status: "True"
        type: Ready
      - lastProbeTime: null
        lastTransitionTime: {{ $now | Quote }}
        message: ''
        reason: ''
        status: "True"
        type: ContainersReady
      containerStatuses:
      {{ range $index, $item := .spec.containers }}
      {{ $origin := index $root.status.containerStatuses $index }}
      - image: {{ $item.image | Quote }}
        name: {{ $item.name | Quote }}
        ready: true
        restartCount: 0
        started: true
        state:
          running:
            startedAt: {{ $now | Quote }}
      {{ end }}
      phase: Running
---
kind: Stage
apiVersion: kwok.x-k8s.io/v1alpha1
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
      - key: '.status.conditions.[] | select( .type == "Ready" ) | .status'
        operator: 'In'
        values:
          - 'True'
      - key: '.metadata.ownerReferences.[].kind'
        operator: 'In'
        values:
          - 'Job'
  weight: 1
  delay:
    durationMilliseconds: 5000
    durationFrom:
      expressionFrom: '.metadata.annotations["pod-complete.stage.kwok.x-k8s.io/delay"]'
    # jitterDurationMilliseconds: 0
    jitterDurationFrom:
      expressionFrom: '.metadata.annotations["pod-complete.stage.kwok.x-k8s.io/jitter-delay"]'
  next:
    delete: false
    statusTemplate: |
      {{ $now := Now }}
      {{ $root := . }}
      containerStatuses:
      {{ range $index, $item := .spec.containers }}
      {{ $origin := index $root.status.containerStatuses $index }}
      - image: {{ $item.image | Quote }}
        name: {{ $item.name | Quote }}
        ready: true
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
kind: Stage
apiVersion: kwok.x-k8s.io/v1alpha1
metadata:
  name: pod-remove-finalizer
spec:
  resourceRef:
    apiGroup: v1
    kind: Pod
  selector:
    matchExpressions:
      - key: '.metadata.deletionTimestamp'
        operator: 'Exists'
      - key: '.metadata.finalizers.[]'
        operator: 'In'
        values:
          - 'kwok.x-k8s.io/fake'
  weight: 1
  delay:
    durationMilliseconds: 5000
    durationFrom:
      expressionFrom: '.metadata.annotations["pod-remove-finalizer.stage.kwok.x-k8s.io/delay"]'
    # jitterDurationMilliseconds: 0
    jitterDurationFrom:
      expressionFrom: '.metadata.annotations["pod-remove-finalizer.stage.kwok.x-k8s.io/jitter-delay"]'
  next:
    finalizers:
      remove:
        - value: 'kwok.x-k8s.io/fake'
    event:
      type: Normal
      reason: Killing
      message: Stopping container
---
kind: Stage
apiVersion: kwok.x-k8s.io/v1alpha1
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
      - key: '.metadata.finalizers'
        operator: 'DoesNotExist'
  weight: 1
  delay:
    durationMilliseconds: 1000
    durationFrom:
      expressionFrom: '.metadata.annotations["pod-remove-finalizer.stage.kwok.x-k8s.io/delay"]'
    jitterDurationFrom:
      expressionFrom: '.metadata.deletionTimestamp'
  next:
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

echo "general-stages.yaml criado."

echo "Tudo pronto!"
