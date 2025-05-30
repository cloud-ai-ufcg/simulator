#!/bin/bash
set -euo pipefail

# CONFIGURÁVEIS
RELEASE_NAME="autoscaler-kwok"
AUTOSCALER_VERSION="v1.32.1"
NAMESPACE="default"

echo "[0/10] Selecionando contexto member2..."
export KUBECONFIG=~/.kube/members.config
kubectl config use-context member2

echo "[1/10] Instalando o KWOK..."
KWOK_REPO="kubernetes-sigs/kwok"
KWOK_LATEST_RELEASE=$(curl -s "https://api.github.com/repos/${KWOK_REPO}/releases/latest" | jq -r '.tag_name')

kubectl apply -f "https://github.com/${KWOK_REPO}/releases/download/${KWOK_LATEST_RELEASE}/kwok.yaml"
kubectl apply -f "https://github.com/${KWOK_REPO}/releases/download/${KWOK_LATEST_RELEASE}/stage-fast.yaml"

echo "[2/10] Aguardando KWOK ficar pronto..."
KWOK_NAMESPACE=$(kubectl get deployment --all-namespaces | grep kwok-controller | awk '{print $1}')
kubectl rollout status deployment/kwok-controller -n "$KWOK_NAMESPACE" --timeout=120s

echo "[3/10] Gerando kubeconfig de member2 para o autoscaler..."
kubectl config view --raw --context member2 > kwok.kubeconfig

kubectl create configmap kwok-kubeconfig \
  --from-file=kwok.kubeconfig=kwok.kubeconfig \
  -n "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

echo "[4/10] Aplicando ConfigMap kwok-provider-config..."
kubectl apply -f kwok-provider-config.yaml
kubectl annotate configmap kwok-provider-config \
  meta.helm.sh/release-name=$RELEASE_NAME \
  meta.helm.sh/release-namespace=$NAMESPACE --overwrite
kubectl label configmap kwok-provider-config \
  app.kubernetes.io/managed-by=Helm --overwrite

echo "[5/10] Instalando Cluster Autoscaler via Helm..."
if [ ! -d "autoscaler" ]; then
  echo "[ERRO] Diretório 'autoscaler/' não encontrado. Clone com:"
  echo "git clone https://github.com/kubernetes/autoscaler.git"
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

echo "[6/10] Aguardando Cluster Autoscaler ficar pronto..."
AUTOSCALER_LABEL=$(kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/instance=$RELEASE_NAME -o jsonpath="{.items[0].metadata.labels['app\.kubernetes\.io/name']}")
kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name="$AUTOSCALER_LABEL" -n "$NAMESPACE" --timeout=120s

echo "[7/10] Aplicando ConfigMap kwok-provider-templates..."
kubectl apply -f kwok-provider-templates.yaml
kubectl annotate configmap kwok-provider-templates \
  meta.helm.sh/release-name=$RELEASE_NAME \
  meta.helm.sh/release-namespace=$NAMESPACE --overwrite
kubectl label configmap kwok-provider-templates \
  app.kubernetes.io/managed-by=Helm --overwrite

echo "[8/10] Tainting node de controle de member2..."
CONTROL_PLANE=$(kubectl get nodes -o name | grep control-plane | sed 's|node/||')
kubectl taint nodes "$CONTROL_PLANE" node-role.kubernetes.io/control-plane=:NoSchedule --overwrite

echo "[9/10] Aplicando deployment de stress..."
kubectl apply -f stress.yaml

echo "[Finalizado] Verifique os pods e logs do autoscaler abaixo:"
kubectl get pods -n "$NAMESPACE"

