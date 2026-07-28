#!/bin/bash
# -----------------------------------------------------------------------------
# Baseline Setup – reconfigures a running WASP environment for the
# Karmada-native baseline (Approach B): no AI, placement driven purely by
# the karmada-scheduler.
# -----------------------------------------------------------------------------
# ‣ Behaviour
#   • Patches karmada-scheduler feature gates
#     (CustomizedClusterResourceModeling=false): the resource-models path of
#     the general estimator ignores current usage and caps clusters at
#     nodes×grade-minimum, which would wreck the capacity-aware member1-first
#     placement.
#   • Scales karmada-scheduler-estimator-member2 to 0 so member2's capacity
#     comes from the general estimator only (which sees the virtual node).
#   • Scales karmada-descheduler to 0: its partial evictions would let the
#     scheduler split one workload across clusters.
#   • Creates the huge tainted 'member2-virtual-capacity' KWOK node.
#   • Swaps the AI ClusterPropagationPolicies for baseline-policy.yaml.
#   • Rebuilds/restarts the monitor container so its Prometheus queries
#     exclude the virtual node.
#
# Reverted by teardown_baseline.sh.
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

# -----------------------------------------------------------------------------
# 0. Preflight
# -----------------------------------------------------------------------------
echo -e "${COLOR}[0/6] 🔍 Checking that the infrastructure is running...${RESET}"
for c in infra-environment karmada-host-control-plane member1-control-plane member2-control-plane; do
  if ! docker ps --format '{{.Names}}' | grep -qx "$c"; then
    echo -e "${COLOR}❌ Container '$c' is not running. Run 'make setup' first.${RESET}"
    exit 1
  fi
done

# -----------------------------------------------------------------------------
# 1. karmada-scheduler: disable CustomizedClusterResourceModeling
# -----------------------------------------------------------------------------
echo -e "${COLOR}[1/6] ⚙️  Patching karmada-scheduler feature gates...${RESET}"
SCHED_JSON=$($KCTL $HOST -n karmada-system get deploy karmada-scheduler -o json)
if echo "$SCHED_JSON" | grep -q 'CustomizedClusterResourceModeling=false'; then
  echo -e "${COLOR}   Already patched. Skipping.${RESET}"
elif echo "$SCHED_JSON" | grep -q 'AllAlpha=true,AllBeta=true'; then
  echo "$SCHED_JSON" \
    | sed 's/AllAlpha=true,AllBeta=true/AllAlpha=true,AllBeta=true,CustomizedClusterResourceModeling=false/' \
    | $KCTL $HOST apply -f -
  $KCTL $HOST -n karmada-system rollout status deploy/karmada-scheduler --timeout=180s
else
  echo -e "${COLOR}❌ Unexpected karmada-scheduler --feature-gates value; refusing to patch blindly.${RESET}"
  echo -e "${COLOR}   Add ',CustomizedClusterResourceModeling=false' to it manually and re-run.${RESET}"
  exit 1
fi

# -----------------------------------------------------------------------------
# 2. Estimator asymmetry: keep member1 precise, make member2 summary-based
# -----------------------------------------------------------------------------
echo -e "${COLOR}[2/6] 📏 Scaling karmada-scheduler-estimator-member2 to 0...${RESET}"
$KCTL $HOST -n karmada-system scale deploy karmada-scheduler-estimator-member2 --replicas=0

# -----------------------------------------------------------------------------
# 3. Descheduler off (partial evictions could split a workload)
# -----------------------------------------------------------------------------
echo -e "${COLOR}[3/6] 🛑 Scaling karmada-descheduler to 0...${RESET}"
$KCTL $HOST -n karmada-system scale deploy karmada-descheduler --replicas=0

# -----------------------------------------------------------------------------
# 4. Virtual elastic-capacity node in member2
# -----------------------------------------------------------------------------
echo -e "${COLOR}[4/6] ☁️  Creating member2-virtual-capacity node...${RESET}"
$KCTL $MEMBER2 apply -f - < "$SCRIPT_DIR/virtual-capacity-node.yaml"
for i in {1..12}; do
  if $KCTL $MEMBER2 get node member2-virtual-capacity --no-headers 2>/dev/null | grep -qw Ready; then
    break
  fi
  sleep 5
done
$KCTL $MEMBER2 get node member2-virtual-capacity

# -----------------------------------------------------------------------------
# 5. Swap propagation policies
# -----------------------------------------------------------------------------
echo -e "${COLOR}[5/6] 📦 Replacing AI propagation policies with baseline-native...${RESET}"
$KCTL $KARMADA delete clusterpropagationpolicy deploy-member1 deploy-member2 deploy-default --ignore-not-found
$KCTL $KARMADA apply -f - < "$SCRIPT_DIR/baseline-policy.yaml"

# -----------------------------------------------------------------------------
# 6. Rebuild monitor so its queries exclude the virtual node
# -----------------------------------------------------------------------------
echo -e "${COLOR}[6/6] 📊 Rebuilding monitor container (virtual-node query filter)...${RESET}"
docker compose -f "$ROOT_DIR/simulator-infra.yaml" build monitor
docker compose -f "$ROOT_DIR/simulator-infra.yaml" up -d --no-deps monitor

# -----------------------------------------------------------------------------
# Final report
# -----------------------------------------------------------------------------
echo -e "\n${COLOR}✅ Baseline environment ready.${RESET}"
echo -e "${COLOR}   member2 allocatable (should include the 100000-CPU virtual node):${RESET}"
$KCTL $KARMADA get cluster member2 -o jsonpath='{.status.resourceSummary.allocatable.cpu}'; echo
echo -e "${COLOR}   Next: 'make run-baseline' (uses the same input.json / metrics pipeline as the AI runs).${RESET}"
