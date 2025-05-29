#!/bin/bash
set -euo pipefail

# CONFIGURÁVEIS
CLUSTER_NAME="teste"
KWOK_REPO="kubernetes-sigs/kwok"
AUTOSCALER_VERSION="v1.32.1"
NAMESPACE="default"

echo "[1/10] Criando cluster KIND: $CLUSTER_NAME..."

echo "[2/10] Instalando o KWOK..."
KWOK_LATEST_RELEASE=$(curl -s "https://api.github.com/repos/${KWOK_REPO}/releases/latest" | jq -r '.tag_name')

kubectl apply -f "https://github.com/${KWOK_REPO}/releases/download/${KWOK_LATEST_RELEASE}/kwok.yaml"
kubectl apply -f "https://github.com/${KWOK_REPO}/releases/download/${KWOK_LATEST_RELEASE}/stage-fast.yaml"

echo "[3/10] Aguardando KWOK ficar pronto..."
KWOK_NAMESPACE=$(kubectl get deployment --all-namespaces | grep kwok-controller | awk '{print $1}')
kubectl rollout status deployment/kwok-controller -n "$KWOK_NAMESPACE" --timeout=120s

echo "[4/10] Gerando kubeconfig para o Autoscaler..."
kind get kubeconfig --name "$CLUSTER_NAME" > kwok.kubeconfig

CONTROL_PLANE=$(docker ps --format '{{.Names}}' | grep "${CLUSTER_NAME}-control-plane")
CLUSTER_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$CONTROL_PLANE")

sed -i "s|server: https://127.0.0.1:[0-9]*|server: https://${CLUSTER_IP}:6443|" kwok.kubeconfig

kubectl create configmap kwok-kubeconfig \
  --from-file=kwok.kubeconfig=kwok.kubeconfig \
  -n "$NAMESPACE"

echo "[5/10] Aplicando ConfigMap kwok-provider-config..."
kubectl apply -f kwok-provider-config.yaml
kubectl annotate configmap kwok-provider-config \
  meta.helm.sh/release-name=autoscaler-kwok \
  meta.helm.sh/release-namespace="$NAMESPACE" --overwrite
kubectl label configmap kwok-provider-config \
  app.kubernetes.io/managed-by=Helm --overwrite

echo "[6/10] Instalando Cluster Autoscaler via Helm..."
if [ ! -d "autoscaler" ]; then
  echo "[ERRO] Diretório 'autoscaler/' não encontrado. Clone com:"
  echo "git clone https://github.com/kubernetes/autoscaler.git"
  exit 1
fi
cd autoscaler

helm upgrade --install autoscaler-kwok charts/cluster-autoscaler \
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

echo "[7/10] Aguardando Cluster Autoscaler ficar pronto..."
AUTOSCALER_LABEL=$(kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/instance=autoscaler-kwok -o jsonpath="{.items[0].metadata.labels['app\.kubernetes\.io/name']}")
kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name="$AUTOSCALER_LABEL" -n "$NAMESPACE" --timeout=120s
cd ..

echo "[8/10] Aplicando ConfigMap kwok-provider-templates..."
kubectl apply -f kwok-provider-templates.yaml
kubectl annotate configmap kwok-provider-templates \
  meta.helm.sh/release-name=autoscaler-kwok \
  meta.helm.sh/release-namespace="$NAMESPACE" --overwrite
kubectl label configmap kwok-provider-templates \
  app.kubernetes.io/managed-by=Helm --overwrite

echo "[9/10] Tainting node de controle..."
kubectl taint nodes "$CONTROL_PLANE" node-role.kubernetes.io/control-plane=:NoSchedule --overwrite

echo "[10/10] Aplicando deployment de stress..."
kubectl apply -f stress.yaml

echo "[Finalizado] Verifique os pods e logs do autoscaler abaixo:"
kubectl get pods -n "$NAMESPACE"
