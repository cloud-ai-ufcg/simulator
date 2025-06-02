#!/bin/bash
set -euo pipefail

# CONFIGURABLE
RELEASE_NAME="autoscaler-kwok"
AUTOSCALER_VERSION="v1.32.1"
NAMESPACE="default"

# Color (Blue for this script)
COLOR="\033[1;34m"
RESET="\033[0m"

echo -e "${COLOR}[0/8] Selecting member2 context...${RESET}"
export KUBECONFIG=~/.kube/members.config
kubectl config use-context member2

echo -e "${COLOR}[1/8] Installing KWOK...${RESET}"
KWOK_REPO="kubernetes-sigs/kwok"
KWOK_LATEST_RELEASE=$(curl -s "https://api.github.com/repos/${KWOK_REPO}/releases/latest" | jq -r '.tag_name')

kubectl apply -f "https://github.com/${KWOK_REPO}/releases/download/${KWOK_LATEST_RELEASE}/kwok.yaml"
kubectl apply -f "https://github.com/${KWOK_REPO}/releases/download/${KWOK_LATEST_RELEASE}/stage-fast.yaml"

echo -e "${COLOR}[2/8] Waiting for KWOK to be ready...${RESET}"
KWOK_NAMESPACE=$(kubectl get deployment --all-namespaces | grep kwok-controller | awk '{print $1}')
kubectl rollout status deployment/kwok-controller -n "$KWOK_NAMESPACE" --timeout=120s

echo -e "${COLOR}[3/8] Generating kubeconfig for member2 to be used by the autoscaler...${RESET}"
kubectl config view --raw --context member2 > kwok.kubeconfig

if kubectl get configmap kwok-kubeconfig -n "$NAMESPACE" &>/dev/null; then
  echo -e "${COLOR}[INFO] ConfigMap 'kwok-kubeconfig' already exists. Skipping creation.${RESET}"
else
  echo -e "${COLOR}[INFO] Creating ConfigMap 'kwok-kubeconfig'...${RESET}"
  kubectl create configmap kwok-kubeconfig \
    --from-file=kwok.kubeconfig=kwok.kubeconfig \
    -n "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
fi

echo -e "${COLOR}[4/8] Applying kwok-provider-config ConfigMap...${RESET}"
kubectl apply -f kwok-provider-config.yaml
kubectl annotate configmap kwok-provider-config \
  meta.helm.sh/release-name=$RELEASE_NAME \
  meta.helm.sh/release-namespace=$NAMESPACE --overwrite
kubectl label configmap kwok-provider-config \
  app.kubernetes.io/managed-by=Helm --overwrite

echo -e "${COLOR}[5/8] Installing Cluster Autoscaler via Helm...${RESET}"
if [ ! -d "autoscaler" ]; then
  echo -e "${COLOR}[ERROR] 'autoscaler/' directory not found. Clone it using:${RESET}"
  echo -e "${COLOR}git clone https://github.com/kubernetes/autoscaler.git${RESET}"
  exit 1
fi
cd autoscaler

helm upgrade --install "$RELEASE_NAME" charts/cluster-autoscaler \
  --namespace "$NAMESPACE" \
  --wait \
  --set cloudProvider=kwok \
  --set image.tag="$AUTOSCALER_VERSION" \
  --set image.repository="registry.k8s.io/autoscaling/cluster-autoscaler" \
  --set extraArgs.v="4" \
  --set extraArgs.logtostderr="true" \
  --set extraArgs.stderrthreshold="info" \
  --set extraArgs.kubeconfig="/etc/kubeconfig/kwok.kubeconfig" \
  --set serviceMonitor.enabled=false \
  --set autoscalingGroups[0].name=dummy \
  --set autoscalingGroups[0].minSize=0 \
  --set autoscalingGroups[0].maxSize=5 \
  --set extraVolumeMounts[0].name=kwok-kubeconfig \
  --set extraVolumeMounts[0].mountPath="/etc/kubeconfig" \
  --set extraVolumeMounts[0].readOnly=true \
  --set extraVolumes[0].name=kwok-kubeconfig \
  --set extraVolumes[0].configMap.name=kwok-kubeconfig

cd ..

echo -e "${COLOR}[6/8] Waiting for Cluster Autoscaler to be ready...${RESET}"
AUTOSCALER_LABEL=$(kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/instance=$RELEASE_NAME -o jsonpath="{.items[0].metadata.labels['app\.kubernetes\.io/name']}")
kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name="$AUTOSCALER_LABEL" -n "$NAMESPACE" --timeout=120s

echo -e "${COLOR}[7/8] Applying kwok-provider-templates ConfigMap...${RESET}"
kubectl apply -f kwok-provider-templates.yaml
kubectl annotate configmap kwok-provider-templates \
  meta.helm.sh/release-name=$RELEASE_NAME \
  meta.helm.sh/release-namespace=$NAMESPACE --overwrite
kubectl label configmap kwok-provider-templates \
  app.kubernetes.io/managed-by=Helm --overwrite

echo -e "${COLOR}[8/8] Tainting control-plane node of member2...${RESET}"
CONTROL_PLANE=$(kubectl get nodes -o name | grep control-plane | sed 's|node/||')
kubectl taint nodes "$CONTROL_PLANE" node-role.kubernetes.io/control-plane=:NoSchedule --overwrite