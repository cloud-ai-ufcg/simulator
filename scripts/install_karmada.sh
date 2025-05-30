#!/bin/bash
set -e

echo "🚀 Subindo ambiente local do Karmada..."
if [ ! -d "karmada" ]; then
  echo "[INFO] Clonando repositório Karmada..."
  git clone https://github.com/karmada-io/karmada.git
else
  echo "[INFO] Repositório Karmada já existe. Pulando clone."
fi
cd karmada
export CLUSTER_NUM=1
hack/local-up-karmada.sh
cd ..

echo "🔧 Configurando KUBECONFIG para karmada-apiserver..."
export KUBECONFIG=~/.kube/karmada.config
kubectl config use-context karmada-apiserver

echo "🏷️ Rotulando clusters..."
kubectl label cluster member1 cloud=private --overwrite
kubectl label cluster member2 cloud=public --overwrite

echo "📦 Verificando se políticas de propagação já existem..."
if ! kubectl get clusterpropagationpolicy deploy-private >/dev/null 2>&1; then
  echo "🔧 Criando políticas de propagação..."
  kubectl create -f clusterpropagationpolicy.yaml
else
  echo "✅ Políticas de propagação já existem. Pulando criação."
fi

echo "🧹 Removendo o cluster member3..."
export KUBECONFIG=~/.kube/members.config
kubectl config delete-context member3 || true
kubectl config delete-cluster kind-member3 || true
