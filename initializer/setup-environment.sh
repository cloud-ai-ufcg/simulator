#!/bin/bash

KUBE_PATH="$HOME/.kube"

# Setup the infrastructure environment
docker compose up -d infra-environment

echo "Waiting for Karmada config to be generated..."
while [ ! -s "$KUBE_PATH/karmada.config" ] || [ ! -s "$KUBE_PATH/members.config" ]; do
    sleep 10
done

# Up the remaining services
docker compose config --services | grep -v infra-environment | xargs docker compose up -d