#!/bin/bash
set -e

CLUSTER_NAME=teste

echo "[1/1] Criando cluster KIND com nó de controle e nó worker..."
kind create cluster --name "$CLUSTER_NAME" --config kind-config.yaml

echo "✅ Cluster '$CLUSTER_NAME' criado com sucesso!"
