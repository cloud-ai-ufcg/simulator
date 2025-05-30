#!/bin/bash
set -euo pipefail

# Verificar se o repositório autoscaler já existe
if [ ! -d "autoscaler" ]; then
  echo "[INFO] Diretório 'autoscaler/' não encontrado. Clonando repositório..."
  git clone --depth 1 https://github.com/kubernetes/autoscaler.git
else
  echo "[INFO] Diretório 'autoscaler/' já existe. Pulando clone."
fi


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

# Gerar clusterpropagationpolicy.yaml
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
      labelSelector: {}  # qualquer cluster
    replicaScheduling:
      replicaSchedulingType: Divided
      replicaDivisionPreference: Weighted
EOF

echo "[OK] clusterpropagationpolicy.yaml gerado com sucesso."


echo
echo "[OK] Arquivos gerados com sucesso:"
ls -1 kwok-provider-config.yaml kwok-provider-templates.yaml stress.yaml kind-config.yaml clusterpropagationpolicy.yaml
