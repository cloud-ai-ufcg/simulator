#!/bin/bash

set -e

echo "🚀 Subindo ambiente local do Karmada..."
cd karmada
export CLUSTER_NUM=1
hack/local-up-karmada.sh
cd ..

echo "🔧 Configurando KUBECONFIG para karmada-apiserver..."
export KUBECONFIG=~/.kube/karmada.config
kubectl config use-context karmada-apiserver

echo "🏷️ Rotulando clusters..."
kubectl label cluster member1 cloud=private 
kubectl label cluster member2 cloud=public 

echo "📦 Verificando se políticas de propagação já existem..."
if ! kubectl get clusterpropagationpolicy deploy-private >/dev/null 2>&1; then
  echo "🔧 Criando políticas de propagação..."
  kubectl create -f clusterpropagationpolicy.yaml
else
  echo "✅ Políticas de propagação já existem. Pulando criação."
fi

echo "🔧 Configurando KUBECONFIG para os membros..."
export KUBECONFIG=~/.kube/members.config
kubectl config use-context member1

KWOK_REPO=kubernetes-sigs/kwok
KWOK_LATEST_RELEASE=$(curl -s "https://api.github.com/repos/${KWOK_REPO}/releases/latest" | jq -r '.tag_name')

echo "📥 Instalando KWOK no member1..."
kubectl apply -f "https://github.com/${KWOK_REPO}/releases/download/${KWOK_LATEST_RELEASE}/kwok.yaml"
kubectl apply -f "https://github.com/${KWOK_REPO}/releases/download/${KWOK_LATEST_RELEASE}/stage-fast.yaml"
kubectl apply -f general-stages.yaml

# echo "🚫 Tainting node de controle member1..."
# kubectl taint nodes member1-control-plane node-role.kubernetes.io/control-plane=:NoSchedule

kubectl config use-context member2

echo "📥 Instalando KWOK no member2..."
kubectl apply -f "https://github.com/${KWOK_REPO}/releases/download/${KWOK_LATEST_RELEASE}/kwok.yaml"
kubectl apply -f "https://github.com/${KWOK_REPO}/releases/download/${KWOK_LATEST_RELEASE}/stage-fast.yaml"
kubectl apply -f general-stages.yaml

echo "📝 Gerando kubeconfig para member2-control-plane..."
kind get kubeconfig --name member2 > kwok.kubeconfig

echo "🔍 Obtendo IP do container member2-control-plane..."
NODE_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' member2-control-plane)

if [ -z "$NODE_IP" ]; then
  echo "❌ IP do container member2-control-plane não encontrado."
  exit 1
fi

echo "🌐 Atualizando servidor no kwok.kubeconfig com IP: $NODE_IP..."
sed -i "s|^    server: https://.*|    server: https://${NODE_IP}:6443|" kwok.kubeconfig

echo "📦 Criando ConfigMap com kubeconfig do KWOK..."
kubectl create configmap kwok-kubeconfig --from-file=kwok.kubeconfig=kwok.kubeconfig -n default

echo "📥 Aplicando kwok-provider-config.yaml..."
kubectl apply -f kwok-provider-config.yaml
kubectl annotate configmap kwok-provider-config \
  meta.helm.sh/release-name=autoscaler-kwok \
  meta.helm.sh/release-namespace=default --overwrite
kubectl label configmap kwok-provider-config \
  app.kubernetes.io/managed-by=Helm --overwrite

echo "📥 Aplicando kwok-provider-templates.yaml..."
kubectl apply -f kwok-provider-templates.yaml
kubectl annotate configmap kwok-provider-templates \
  meta.helm.sh/release-name=autoscaler-kwok \
  meta.helm.sh/release-namespace=default --overwrite
kubectl label configmap kwok-provider-templates \
  app.kubernetes.io/managed-by=Helm --overwrite

sleep 10
echo "🚀 Instalando Cluster Autoscaler via Helm..."
cd autoscaler
helm upgrade --install autoscaler-kwok charts/cluster-autoscaler \
--namespace default \
--set cloudProvider=kwok \
--set image.tag="v1.32.1" \
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

echo "⏳ Aguardando o pod do Cluster Autoscaler ficar pronto..."
until kubectl wait pod -n default -l app.kubernetes.io/name=kwok-cluster-autoscaler \
  --for=condition=Ready --timeout=300s; do
  echo "🔄 Esperando o Cluster Autoscaler ficar pronto..."
  sleep 5
done
echo "✅ Cluster Autoscaler está pronto."

echo "🚫 Tainting node de controle member2..."
# kubectl taint nodes member2-control-plane node-role.kubernetes.io/control-plane=:NoSchedule

echo "✅ Ambiente Karmada com Autoscaler configurado com sucesso!"