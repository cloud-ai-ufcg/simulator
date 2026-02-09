#!/bin/bash
set -e 

KUBE_PATH="$HOME/.kube"

# Clean up existing Karmada and members config files if they are empty
sudo rm -f "$KUBE_PATH/karmada.config" "$KUBE_PATH/members.config"

# Setup the infrastructure environment
docker compose up -d infra-environment

# Wait until the Karmada and members config files are generated
echo "Waiting for Karmada config to be generated..."
while [ ! -s "$KUBE_PATH/karmada.config" ] || [ ! -s "$KUBE_PATH/members.config" ]; do
    sleep 10
done

# Up the remaining services
docker compose config --services | grep -v infra-environment | xargs docker compose up -d