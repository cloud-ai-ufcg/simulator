#!/bin/bash
# -----------------------------------------------------------------------------
# Baseline Teardown – restores the environment reconfigured by
# setup_baseline.sh back to the AI-driven (Approach A) configuration.
# -----------------------------------------------------------------------------
COLOR="\033[1;36m"  # Cyan – baseline scripts identity color
RESET="\033[0m"

set -euo pipefail
trap 'echo -e "${COLOR}❌ Error in ${BASH_SOURCE[0]}:$LINENO – $BASH_COMMAND${RESET}"' ERR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

KCTL="docker exec -i infra-environment kubectl"
KARMADA="--kubeconfig /root/.kube/karmada.config --context karmada-apiserver"
HOST="--kubeconfig /root/.kube/karmada.config --context karmada-host"
MEMBER2="--kubeconfig /root/.kube/members.config --context member2"

echo -e "${COLOR}[1/5] 📦 Restoring AI propagation policies...${RESET}"
$KCTL $KARMADA delete clusterpropagationpolicy baseline-native --ignore-not-found
$KCTL $KARMADA apply -f - < "$ROOT_DIR/scripts/clusterpropagationpolicy.yaml"

echo -e "${COLOR}[2/5] ☁️  Removing member2-virtual-capacity node...${RESET}"
$KCTL $MEMBER2 delete node member2-virtual-capacity --ignore-not-found

echo -e "${COLOR}[3/5] 📏 Restoring karmada-scheduler-estimator-member2...${RESET}"
$KCTL $HOST -n karmada-system scale deploy karmada-scheduler-estimator-member2 --replicas=2

echo -e "${COLOR}[4/5] ▶️  Restoring karmada-descheduler...${RESET}"
$KCTL $HOST -n karmada-system scale deploy karmada-descheduler --replicas=2

echo -e "${COLOR}[5/5] ⚙️  Restoring karmada-scheduler feature gates...${RESET}"
SCHED_JSON=$($KCTL $HOST -n karmada-system get deploy karmada-scheduler -o json)
if echo "$SCHED_JSON" | grep -q ',CustomizedClusterResourceModeling=false'; then
  echo "$SCHED_JSON" \
    | sed 's/,CustomizedClusterResourceModeling=false//' \
    | $KCTL $HOST apply -f -
  $KCTL $HOST -n karmada-system rollout status deploy/karmada-scheduler --timeout=180s
else
  echo -e "${COLOR}   Feature gates already at original value. Skipping.${RESET}"
fi

echo -e "\n${COLOR}✅ Environment restored to the AI-driven configuration.${RESET}"
