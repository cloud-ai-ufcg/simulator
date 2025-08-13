#!/bin/bash
# -----------------------------------------------------------------------------
# Cluster Autoscaler Installer – installs CA with KWOK provider in member2.
# Also applies the shared kubeconfig and KWOK provider templates to both clusters.
# -----------------------------------------------------------------------------
# ‣ Behaviour
#   • Creates a configMap from member2's kubeconfig.
#   • Applies kwok-provider-config.yaml.
#   • Conditionally installs Cluster Autoscaler via Helm in member2.
#   • Applies kwok-provider-templates to member1 and optionally member2.
# -----------------------------------------------------------------------------
COLOR="\033[1;34m"  # Blue
RESET="\033[0m"

set -euo pipefail
trap 'echo -e "${COLOR}❌ Error in ${BASH_SOURCE[0]}:$LINENO – $BASH_COMMAND${RESET}"' ERR

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------
RELEASE_NAME="autoscaler-kwok"
AUTOSCALER_VERSION="v1.32.1"
NAMESPACE="autoscaler"

export KUBECONFIG=~/.kube/members.config

echo -e "${COLOR}[INFO] Autoscaler enabled for member2: ${MEMBER2_AUTOSCALER}${RESET}"
echo -e "${COLOR}🔧 Creating namespace '$NAMESPACE' (if needed)...${RESET}"
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

# -----------------------------------------------------------------------------
# 1. Generate kubeconfig ConfigMap for member2
# -----------------------------------------------------------------------------
echo -e "${COLOR}[1/5] Generating kubeconfig for member2...${RESET}"
kubectl config view --raw --context member2 > kwok.kubeconfig

if kubectl get configmap kwok-kubeconfig -n "$NAMESPACE" &>/dev/null; then
  echo -e "${COLOR}[INFO] ConfigMap 'kwok-kubeconfig' already exists. Skipping creation.${RESET}"
else
  kubectl create configmap kwok-kubeconfig \
    --from-file=kwok.kubeconfig=kwok.kubeconfig \
    -n "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
fi

# -----------------------------------------------------------------------------
# 2. Apply KWOK provider configuration
# -----------------------------------------------------------------------------
echo -e "${COLOR}[2/5] Applying kwok-provider-config ConfigMap...${RESET}"
kubectl apply -f kwok-provider-config.yaml
kubectl annotate configmap kwok-provider-config \
  meta.helm.sh/release-name=$RELEASE_NAME \
  meta.helm.sh/release-namespace=$NAMESPACE --overwrite
kubectl label configmap kwok-provider-config \
  app.kubernetes.io/managed-by=Helm --overwrite

# -----------------------------------------------------------------------------
# 3. Optionally install Cluster Autoscaler via Helm
# -----------------------------------------------------------------------------
if [[ "${MEMBER2_AUTOSCALER:-true}" == "true" ]]; then
  echo -e "${COLOR}[3/5] Installing Cluster Autoscaler via Helm...${RESET}"

  if [ ! -d "autoscaler" ]; then
    echo -e "${COLOR}[ERROR] 'autoscaler/' directory not found. Cloning it...${RESET}"
    git clone https://github.com/cloud-ai-ufcg/autoscaler.git
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
    --set extraVolumes[0].configMap.name=kwok-kubeconfig \
    --set autoscalerResources.member.cpu=$MEMBER2_CPU \
    --set autoscalerResources.member.memory=$MEMBER2_MEM \
    --set extraArgs.scale-down-delay-after-add=5m \
    --set extraArgs.scale-down-unneeded-time=0m

  cd ..

  echo -e "${COLOR}[4/5] Waiting for Cluster Autoscaler to be ready...${RESET}"
  AUTOSCALER_LABEL=$(kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/instance=$RELEASE_NAME -o jsonpath="{.items[0].metadata.labels['app\.kubernetes\.io/name']}")
  kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name="$AUTOSCALER_LABEL" -n "$NAMESPACE" --timeout=120s
else
  echo -e "${COLOR}[3/5] Skipping Cluster Autoscaler installation (disabled by config).${RESET}"
fi

# -----------------------------------------------------------------------------
# 4. Apply KWOK provider templates to member1 and optionally member2
# -----------------------------------------------------------------------------
echo -e "${COLOR}[5/5] Applying KWOK provider templates...${RESET}"

echo -e "${COLOR}[member1] Applying kwok-provider-templates-member1.yaml...${RESET}"
kubectl apply -f kwok-provider-templates-member1.yaml --context member1
kubectl annotate configmap kwok-provider-templates kwok.io/reload=$(date +%s) --overwrite --context member1 || true

if [[ "${MEMBER2_AUTOSCALER:-true}" == "true" ]]; then
  echo -e "${COLOR}[member2] Applying kwok-provider-templates-member2.yaml...${RESET}"
  kubectl apply -f kwok-provider-templates-member2.yaml --context member2
  kubectl annotate configmap kwok-provider-templates kwok.io/reload=$(date +%s) --overwrite --context member2 || true
else
  echo -e "${COLOR}[member2] Skipping kwok-provider-templates (autoscaler disabled).${RESET}"
fi

echo -e "${COLOR}✅ Cluster Autoscaler and KWOK provider templates configured.${RESET}"
