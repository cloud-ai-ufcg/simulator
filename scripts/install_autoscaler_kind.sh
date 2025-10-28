#!/bin/bash
# -----------------------------------------------------------------------------
# Cluster Autoscaler Installer for KIND - Install CA with Cluster API provider
# Uses Cluster API Provider for Docker (CAPD) to enable autoscaling with KIND
# -----------------------------------------------------------------------------
# ‣ Behaviour
#   • Installs Cluster API (CAPI)
#   • Installs CAPD (Docker provider)
#   • Configures CA to use clusterapi provider
#   • Enables autoscaling in member2 (public cluster)
# -----------------------------------------------------------------------------
COLOR="\033[1;34m"  # Blue
RESET="\033[0m"

set -euo pipefail
trap 'echo -e "${COLOR}❌ Error in ${BASH_SOURCE[0]}:$LINENO – $BASH_COMMAND${RESET}"' ERR

RELEASE_NAME="cluster-autoscaler"
AUTOSCALER_VERSION="v1.32.1"
NAMESPACE="kube-system"
CAPI_VERSION="v1.6.0"

# Use KUBECONFIG from environment if set, otherwise use members.config
export KUBECONFIG="${KUBECONFIG:-~/.kube/members.config}"

echo -e "${COLOR}🔧 Installing Cluster Autoscaler with Cluster API for KIND...${RESET}"
echo -e "${COLOR}⚠️  This is complex but will enable real autoscaling with KIND${RESET}"

# Switch to member2 context
kubectl config use-context member2

# -----------------------------------------------------------------------------
# 1. Install Cluster API (CAPI)
# -----------------------------------------------------------------------------
echo -e "${COLOR}[1/6] Installing Cluster API (CAPI)...${RESET}"

# Download clusterctl
if ! command -v clusterctl &> /dev/null; then
    echo -e "${COLOR}  Installing clusterctl...${RESET}"
    curl -L https://github.com/kubernetes-sigs/cluster-api/releases/download/${CAPI_VERSION}/clusterctl-linux-amd64 -o clusterctl
    chmod +x clusterctl
    sudo mv clusterctl /usr/local/bin/clusterctl
fi

echo -e "${COLOR}  ✅ clusterctl version: $(clusterctl version)${RESET}"

# Initialize Cluster API
clusterctl init --infrastructure docker

# Wait for CAPI to be ready
echo -e "${COLOR}  ⏳ Waiting for CAPI to be ready...${RESET}"
sleep 30

# -----------------------------------------------------------------------------
# 2. Create a management cluster for CAPI
# -----------------------------------------------------------------------------
echo -e "${COLOR}[2/6] Setting up CAPI management cluster...${RESET}"

# Currently, member2 will act as both workload and management cluster
# This is a simplified approach

# -----------------------------------------------------------------------------
# 3. Install Cluster Autoscaler with clusterapi provider
# -----------------------------------------------------------------------------
echo -e "${COLOR}[3/6] Installing Cluster Autoscaler with clusterapi provider...${RESET}"

cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  labels:
    k8s-app: cluster-autoscaler
  name: cluster-autoscaler
  namespace: ${NAMESPACE}
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: cluster-autoscaler
  labels:
    k8s-app: cluster-autoscaler
rules:
  - apiGroups: [""]
    resources: ["events", "endpoints"]
    verbs: ["create", "patch"]
  - apiGroups: [""]
    resources: ["pods/eviction"]
    verbs: ["create"]
  - apiGroups: [""]
    resources: ["pods/status"]
    verbs: ["update"]
  - apiGroups: [""]
    resources: ["endpoints"]
    resourceNames: ["cluster-autoscaler"]
    verbs: ["get", "update"]
  - apiGroups: [""]
    resources: ["nodes"]
    verbs: ["watch", "list", "get", "update"]
  - apiGroups: [""]
    resources: ["namespaces", "pods", "services", "replicationcontrollers", "persistentvolumeclaims", "persistentvolumes"]
    verbs: ["watch", "list", "get"]
  - apiGroups: ["extensions"]
    resources: ["replicasets", "daemonsets"]
    verbs: ["watch", "list", "get"]
  - apiGroups: ["policy"]
    resources: ["poddisruptionbudgets"]
    verbs: ["watch", "list"]
  - apiGroups: ["apps"]
    resources: ["statefulsets", "replicasets", "daemonsets"]
    verbs: ["watch", "list", "get"]
  - apiGroups: ["storage.k8s.io"]
    resources: ["storageclasses", "csinodes", "csistoragecapacities", "csidrivers"]
    verbs: ["watch", "list", "get"]
  - apiGroups: ["batch", "extensions"]
    resources: ["jobs"]
    verbs: ["get", "list", "watch", "patch"]
  - apiGroups: ["coordination.k8s.io"]
    resources: ["leases"]
    verbs: ["create"]
  - apiGroups: ["coordination.k8s.io"]
    resourceNames: ["cluster-autoscaler"]
    resources: ["leases"]
    verbs: ["get", "update"]
  - apiGroups: ["cluster.x-k8s.io"]
    resources: ["*"]
    verbs: ["*"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: cluster-autoscaler
  labels:
    k8s-app: cluster-autoscaler
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-autoscaler
subjects:
  - kind: ServiceAccount
    name: cluster-autoscaler
    namespace: ${NAMESPACE}
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: cluster-autoscaler
  namespace: ${NAMESPACE}
  labels:
    app: cluster-autoscaler
spec:
  replicas: 1
  selector:
    matchLabels:
      app: cluster-autoscaler
  template:
    metadata:
      labels:
        app: cluster-autoscaler
    spec:
      serviceAccountName: cluster-autoscaler
      containers:
        - image: registry.k8s.io/autoscaling/cluster-autoscaler:${AUTOSCALER_VERSION}
          name: cluster-autoscaler
          resources:
            limits:
              cpu: 100m
              memory: 600Mi
            requests:
              cpu: 100m
              memory: 600Mi
          command:
            - ./cluster-autoscaler
            - --v=4
            - --stderrthreshold=info
            - --cloud-provider=clusterapi
            - --skip-nodes-with-local-storage=false
            - --expander=least-waste
            - --scale-down-delay-after-add=5m
            - --scale-down-unneeded-time=5m
          imagePullPolicy: Always
      nodeSelector:
        kubernetes.io/os: linux
      tolerations:
        - effect: NoSchedule
          operator: Exists
          key: node-role.kubernetes.io/master
        - effect: NoSchedule
          operator: Exists
          key: node-role.kubernetes.io/control-plane
EOF

echo -e "${COLOR}  ✅ Cluster Autoscaler deployment created${RESET}"

# -----------------------------------------------------------------------------
# 4. Wait for Cluster Autoscaler
# -----------------------------------------------------------------------------
echo -e "${COLOR}[4/6] Waiting for Cluster Autoscaler to be ready...${RESET}"
kubectl wait --for=condition=available --timeout=300s deployment/cluster-autoscaler -n "$NAMESPACE" || {
    echo -e "${COLOR}⚠️  Cluster Autoscaler may not be fully ready. Check logs with:${RESET}"
    echo -e "${COLOR}   kubectl logs -n ${NAMESPACE} -l app=cluster-autoscaler${RESET}"
}

# -----------------------------------------------------------------------------
# 5. Create MachinePool for autoscaling
# -----------------------------------------------------------------------------
echo -e "${COLOR}[5/6] Setting up MachinePool for autoscaling...${RESET}"

# Create a MachinePool resource
cat <<EOF | kubectl apply -f -
apiVersion: cluster.x-k8s.io/v1beta1
kind: MachinePool
metadata:
  name: ${RELEASE_NAME}-pool
  namespace: default
spec:
  clusterName: member2-cluster
  replicas: 2
  template:
    spec:
      clusterName: member2-cluster
      bootstrap:
        configRef:
          apiVersion: bootstrap.cluster.x-k8s.io/v1beta1
          kind: KubeadmConfigTemplate
          name: member2-capi-template
      infrastructureRef:
        apiVersion: infrastructure.cluster.x-k8s.io/v1beta1
        kind: DockerMachineTemplate
        name: member2-capi-template
EOF

echo -e "${COLOR}  ✅ MachinePool created${RESET}"

# -----------------------------------------------------------------------------
# 6. Verify installation
# -----------------------------------------------------------------------------
echo -e "${COLOR}[6/6] Verifying Cluster Autoscaler...${RESET}"
kubectl get pods -n "$NAMESPACE" -l app=cluster-autoscaler

echo -e "${COLOR}✅ Cluster Autoscaler with Cluster API installed in member2!${RESET}"
echo -e "${COLOR}📝 Note: This is a complex setup. For production, consider using KWOK or real cloud providers${RESET}"
echo -e "${COLOR}🔍 Check logs with: kubectl logs -n ${NAMESPACE} -l app=cluster-autoscaler${RESET}"
