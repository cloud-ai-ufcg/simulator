#!/bin/bash
set -euo pipefail

# Verificar se o repositório autoscaler já existe
if [ ! -d "autoscaler" ]; then
  echo "[INFO] Diretório 'autoscaler/' não encontrado. Clonando repositório..."
  git clone --depth 1 https://github.com/kubernetes/autoscaler.git
else
  echo "[INFO] Diretório 'autoscaler/' já existe. Pulando clone."
fi

# Gerar kind-config para criacao de cluster
cat > kind-config.yaml <<EOF
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
  - role: control-plane
    kubeadmConfigPatches:
      - |
        kind: InitConfiguration
        nodeRegistration:
          kubeletExtraArgs:
            node-labels: "ingress-ready=true"
            authorization-mode: AlwaysAllow
    extraPortMappings:
      - containerPort: 30090
        hostPort: 30090
        protocol: TCP
  - role: worker
EOF

# Gerar kwok-provider-config.yaml
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

# Gerar kwok-provider-templates.yaml
cat > kwok-provider-templates.yaml <<EOF
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
  config: |
    apiVersion: v1alpha1
    readNodesFrom: configmap
    nodegroups:
      fromNodeLabelKey: "kwok-nodegroup"
    configmap:
      name: kwok-provider-templates
EOF

# Gerar stress.yaml
cat > stress.yaml <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: stress
spec:
  replicas: 30
  selector:
    matchLabels:
      app: stress
  template:
    metadata:
      labels:
        app: stress
    spec:
      containers:
        - name: stress
          image: busybox
          command: ["sh", "-c", "while true; do echo running; sleep 10; done"]
          resources:
            requests:
              cpu: "2"
              memory: "256Mi"
            limits:
              cpu: "2"
              memory: "512Mi"
      tolerations:
        - key: "kwok-provider"
          operator: "Equal"
          value: "true"
          effect: "NoSchedule"
EOF

echo
echo "[OK] Arquivos gerados com sucesso:"
ls -1 kwok-provider-config.yaml kwok-provider-templates.yaml stress.yaml kind-config.yaml
