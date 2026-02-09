#!/bin/bash
set -e 

KUBE_PATH="$HOME/.kube"
INFRAMODE=0
COMPONENTS_ONLY=0


setup_infra() {
    # Setup the infrastructure environment
    docker compose -f simulator-infra.yaml up --build -d infra-environment 

    # Wait until the Karmada and members config files are generated
    echo "Waiting for Karmada config to be generated..."
    while [ ! -s "$KUBE_PATH/karmada.config" ] || [ ! -s "$KUBE_PATH/members.config" ]; do
        sleep 10
    done
}

setup_components() {
    # Up the remaining services
    docker compose -f simulator-infra.yaml config --services | grep -v infra-environment | xargs docker compose -f simulator-infra.yaml up -d
}

check_call() {
    ./check_infra_status.sh
    if [ $? -eq 1 ]; then
        exit 1
    fi
}

# Clean up existing Karmada and members config files if they are empty
sudo rm -f "$KUBE_PATH/karmada.config" "$KUBE_PATH/members.config" "$KUBE_PATH/build.log"

while [[ "$#" -gt 0 ]]; do
    case $1 in
        --inframode) 
            setup_infra
            check_call

            echo "Infrastructure setup completed. Exiting as --inframode flag is set."
            exit 0;;
        --components-only) 
            setup_components

            echo "Components setup completed. Exiting as --components-only flag is set."
            exit 0;;
        *) echo "Opção desconhecida: $1"; exit 1 ;;
    esac
    shift
done


setup_infra
check_call
setup_components