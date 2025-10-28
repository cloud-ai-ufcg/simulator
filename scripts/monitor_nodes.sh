#!/bin/bash

# Script para monitorar nodes, pods e deployments em tempo real
# Mostra quando novos nodes são criados dinamicamente
# Requisitos: kubectl, jq

COLOR="\033[1;36m"  # Cyan
RESET="\033[0m"

export KUBECONFIG=~/.kube/members.config

echo -e "${COLOR}========================================${RESET}"
echo -e "${COLOR}  Monitor de Nodes e Deployments${RESET}"
echo -e "${COLOR}========================================${RESET}"
echo ""
echo -e "${COLOR}Monitoring nodes, pods & deployments... (Ctrl+C to stop)${RESET}"
echo ""

LAST_COUNT_M1=0
LAST_COUNT_M2=0
LAST_PENDING_M1=0
LAST_PENDING_M2=0
LAST_RUNNING_M1=0
LAST_RUNNING_M2=0
LAST_DEPLOY_PENDING_M1=0
LAST_DEPLOY_PENDING_M2=0
LAST_DEPLOY_RUNNING_M1=0
LAST_DEPLOY_RUNNING_M2=0

while true; do
    # Member1 - Nodes
    COUNT_M1=$(kubectl --context member1 get nodes --no-headers 2>/dev/null | wc -l)
    if [ "$COUNT_M1" -ne "$LAST_COUNT_M1" ]; then
        echo -e "\n${COLOR}🆕 MEMBER1: $LAST_COUNT_M1 → $COUNT_M1 nodes${RESET}"
        kubectl --context member1 get nodes
        LAST_COUNT_M1=$COUNT_M1
    fi
    
    # Member1 - Pending Pods
    PENDING_M1=$(kubectl --context member1 get pods -A --field-selector=status.phase=Pending --no-headers 2>/dev/null | wc -l)
    if [ "$PENDING_M1" -ne "$LAST_PENDING_M1" ]; then
        echo -e "\n${COLOR}⚠️  MEMBER1: $LAST_PENDING_M1 → $PENDING_M1 pods pending${RESET}"
        if [ "$PENDING_M1" -gt 0 ]; then
            kubectl --context member1 get pods -A --field-selector=status.phase=Pending --no-headers | head -5
            if [ "$PENDING_M1" -gt 5 ]; then
                echo "... and $((PENDING_M1 - 5)) more"
            fi
        fi
        LAST_PENDING_M1=$PENDING_M1
    fi
    
    # Member1 - Running Pods
    RUNNING_M1=$(kubectl --context member1 get pods -A --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)
    if [ "$RUNNING_M1" -ne "$LAST_RUNNING_M1" ]; then
        echo -e "\n${COLOR}✅ MEMBER1: $LAST_RUNNING_M1 → $RUNNING_M1 pods running${RESET}"
        LAST_RUNNING_M1=$RUNNING_M1
    fi
    
    # Member1 - Deployments with Pending Pods
    DEPLOY_PENDING_M1=$(kubectl --context member1 get deployments -A -o json 2>/dev/null | jq -r '.items[] | select(.status.replicas != .status.readyReplicas and .status.replicas > 0) | .metadata.namespace + "/" + .metadata.name' 2>/dev/null | wc -l)
    if [ "$DEPLOY_PENDING_M1" -ne "$LAST_DEPLOY_PENDING_M1" ]; then
        echo -e "\n${COLOR}🚀 MEMBER1: $LAST_DEPLOY_PENDING_M1 → $DEPLOY_PENDING_M1 deployments waiting (pending pods)${RESET}"
        if [ "$DEPLOY_PENDING_M1" -gt 0 ]; then
            kubectl --context member1 get deployments -A -o json 2>/dev/null | jq -r '.items[] | select(.status.replicas != .status.readyReplicas and .status.replicas > 0) | .metadata.namespace + "/" + .metadata.name + " (" + (.status.replicas|tostring) + "/" + (.status.readyReplicas|tostring) + ")"' 2>/dev/null | head -5
            if [ "$DEPLOY_PENDING_M1" -gt 5 ]; then
                echo "... and $((DEPLOY_PENDING_M1 - 5)) more"
            fi
        fi
        LAST_DEPLOY_PENDING_M1=$DEPLOY_PENDING_M1
    fi
    
    # Member1 - Deployments with Running Pods
    DEPLOY_RUNNING_M1=$(kubectl --context member1 get deployments -A -o json 2>/dev/null | jq -r '.items[] | select(.status.readyReplicas > 0) | .metadata.namespace + "/" + .metadata.name' 2>/dev/null | wc -l)
    if [ "$DEPLOY_RUNNING_M1" -ne "$LAST_DEPLOY_RUNNING_M1" ]; then
        echo -e "\n${COLOR}✔️  MEMBER1: $LAST_DEPLOY_RUNNING_M1 → $DEPLOY_RUNNING_M1 deployments running${RESET}"
        LAST_DEPLOY_RUNNING_M1=$DEPLOY_RUNNING_M1
    fi
    
    # Member2 - Nodes
    COUNT_M2=$(kubectl --context member2 get nodes --no-headers 2>/dev/null | wc -l)
    if [ "$COUNT_M2" -ne "$LAST_COUNT_M2" ]; then
        echo -e "\n${COLOR}🆕 MEMBER2: $LAST_COUNT_M2 → $COUNT_M2 nodes${RESET}"
        kubectl --context member2 get nodes
        LAST_COUNT_M2=$COUNT_M2
    fi
    
    # Member2 - Pending Pods
    PENDING_M2=$(kubectl --context member2 get pods -A --field-selector=status.phase=Pending --no-headers 2>/dev/null | wc -l)
    if [ "$PENDING_M2" -ne "$LAST_PENDING_M2" ]; then
        echo -e "\n${COLOR}⚠️  MEMBER2: $LAST_PENDING_M2 → $PENDING_M2 pods pending${RESET}"
        if [ "$PENDING_M2" -gt 0 ]; then
            kubectl --context member2 get pods -A --field-selector=status.phase=Pending --no-headers | head -5
            if [ "$PENDING_M2" -gt 5 ]; then
                echo "... and $((PENDING_M2 - 5)) more"
            fi
        fi
        LAST_PENDING_M2=$PENDING_M2
    fi
    
    # Member2 - Running Pods
    RUNNING_M2=$(kubectl --context member2 get pods -A --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)
    if [ "$RUNNING_M2" -ne "$LAST_RUNNING_M2" ]; then
        echo -e "\n${COLOR}✅ MEMBER2: $LAST_RUNNING_M2 → $RUNNING_M2 pods running${RESET}"
        LAST_RUNNING_M2=$RUNNING_M2
    fi
    
    # Member2 - Deployments with Pending Pods
    DEPLOY_PENDING_M2=$(kubectl --context member2 get deployments -A -o json 2>/dev/null | jq -r '.items[] | select(.status.replicas != .status.readyReplicas and .status.replicas > 0) | .metadata.namespace + "/" + .metadata.name' 2>/dev/null | wc -l)
    if [ "$DEPLOY_PENDING_M2" -ne "$LAST_DEPLOY_PENDING_M2" ]; then
        echo -e "\n${COLOR}🚀 MEMBER2: $LAST_DEPLOY_PENDING_M2 → $DEPLOY_PENDING_M2 deployments waiting (pending pods)${RESET}"
        if [ "$DEPLOY_PENDING_M2" -gt 0 ]; then
            kubectl --context member2 get deployments -A -o json 2>/dev/null | jq -r '.items[] | select(.status.replicas != .status.readyReplicas and .status.replicas > 0) | .metadata.namespace + "/" + .metadata.name + " (" + (.status.replicas|tostring) + "/" + (.status.readyReplicas|tostring) + ")"' 2>/dev/null | head -5
            if [ "$DEPLOY_PENDING_M2" -gt 5 ]; then
                echo "... and $((DEPLOY_PENDING_M2 - 5)) more"
            fi
        fi
        LAST_DEPLOY_PENDING_M2=$DEPLOY_PENDING_M2
    fi
    
    # Member2 - Deployments with Running Pods
    DEPLOY_RUNNING_M2=$(kubectl --context member2 get deployments -A -o json 2>/dev/null | jq -r '.items[] | select(.status.readyReplicas > 0) | .metadata.namespace + "/" + .metadata.name' 2>/dev/null | wc -l)
    if [ "$DEPLOY_RUNNING_M2" -ne "$LAST_DEPLOY_RUNNING_M2" ]; then
        echo -e "\n${COLOR}✔️  MEMBER2: $LAST_DEPLOY_RUNNING_M2 → $DEPLOY_RUNNING_M2 deployments running${RESET}"
        LAST_DEPLOY_RUNNING_M2=$DEPLOY_RUNNING_M2
    fi
    
    # Status atual
    echo -n "$(date '+%H:%M:%S') - M1: $COUNT_M1 nodes | Pods: ⚠️$PENDING_M1 ✅$RUNNING_M1 | Deploys: 🚀$DEPLOY_PENDING_M1 ✔️$DEPLOY_RUNNING_M1 | M2: $COUNT_M2 nodes | Pods: ⚠️$PENDING_M2 ✅$RUNNING_M2 | Deploys: 🚀$DEPLOY_PENDING_M2 ✔️$DEPLOY_RUNNING_M2     \r"
    
    sleep 5
done
