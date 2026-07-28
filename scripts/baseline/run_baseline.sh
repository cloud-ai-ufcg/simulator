#!/bin/bash
# -----------------------------------------------------------------------------
# Baseline Run – executes one simulation with the Karmada-native baseline.
# -----------------------------------------------------------------------------
# ‣ Behaviour
#   • Verifies setup_baseline.sh has been applied.
#   • Restarts the monitor container so the run starts with a clean
#     metrics window.
#   • Runs the Go simulator with WASP_DISABLE_AI=1: the broker replays
#     data/input.json exactly as in an AI run, but the ai-engine is never
#     called — placement decisions come from karmada-scheduler alone.
#   • While the simulator runs, polls the Karmada API every 30s for
#     ResourceBindings with condition Scheduled=False and appends one JSON
#     line per sample to unschedulable_bindings.jsonl. With the baseline
#     configured correctly this stays at 0 (the virtual node makes the
#     public-burst group always schedulable); the file is the safety net
#     that makes any silent total-scheduling failure visible to the
#     analyzer (analyzer/data_loader.py::load_unschedulable_data).
#   • Moves the .jsonl into the run directory the simulator created, next
#     to metrics.json, where the analyzer expects it.
# -----------------------------------------------------------------------------
COLOR="\033[1;36m"  # Cyan – baseline scripts identity color
RESET="\033[0m"

set -euo pipefail
trap 'echo -e "${COLOR}❌ Error in ${BASH_SOURCE[0]}:$LINENO – $BASH_COMMAND${RESET}"' ERR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
OUTPUT_DIR="$ROOT_DIR/simulator/data/output"

KCTL="docker exec -i infra-environment kubectl"
KARMADA="--kubeconfig /root/.kube/karmada.config --context karmada-apiserver"
MEMBER2="--kubeconfig /root/.kube/members.config --context member2"

# -----------------------------------------------------------------------------
# 1. Preflight: baseline must be set up
# -----------------------------------------------------------------------------
echo -e "${COLOR}[1/4] 🔍 Verifying baseline configuration...${RESET}"
if ! $KCTL $KARMADA get clusterpropagationpolicy baseline-native >/dev/null 2>&1; then
  echo -e "${COLOR}❌ ClusterPropagationPolicy 'baseline-native' not found. Run 'make setup-baseline' first.${RESET}"
  exit 1
fi
if ! $KCTL $MEMBER2 get node member2-virtual-capacity >/dev/null 2>&1; then
  echo -e "${COLOR}❌ Node 'member2-virtual-capacity' not found in member2. Run 'make setup-baseline' first.${RESET}"
  exit 1
fi

# -----------------------------------------------------------------------------
# 2. Fresh metrics window
# -----------------------------------------------------------------------------
echo -e "${COLOR}[2/4] 📊 Restarting monitor for a clean metrics window...${RESET}"
docker restart monitor >/dev/null
for i in {1..24}; do
  if curl --silent --fail --max-time 3 "http://localhost:8082/metrics" >/dev/null 2>&1; then
    break
  fi
  sleep 5
done

# -----------------------------------------------------------------------------
# 3. Unschedulable-bindings poller (30 s) + simulator
# -----------------------------------------------------------------------------
UNSCHED_TMP="$(mktemp /tmp/unschedulable_bindings.XXXXXX.jsonl)"

poll_unschedulable() {
  while true; do
    TS="$(date '+%Y-%m-%d %H:%M:%S')"
    LINE=$(docker exec -e TS="$TS" infra-environment bash -c '
      kubectl --kubeconfig /root/.kube/karmada.config --context karmada-apiserver \
        get resourcebinding -A -o json 2>/dev/null \
      | jq -c --arg ts "$TS" "
          [ .items[]
            | select(((.status.conditions // []) | map(select(.type == \"Scheduled\")) | first // {}).status == \"False\")
            | .metadata.namespace + \"/\" + .metadata.name ]
          | {timestamp: \$ts, unschedulable_count: length, unschedulable_workloads: .}"
    ' 2>/dev/null) || LINE=""
    if [ -n "$LINE" ]; then
      echo "$LINE" >> "$UNSCHED_TMP"
    fi
    sleep 30
  done
}

echo -e "${COLOR}[3/4] 🚀 Starting unschedulable-bindings poller and simulator (AI disabled)...${RESET}"
poll_unschedulable &
POLLER_PID=$!
trap 'kill "$POLLER_PID" 2>/dev/null || true' EXIT

RUN_START_EPOCH=$(date +%s)
(cd "$ROOT_DIR/simulator/cmd" && WASP_DISABLE_AI=1 go run main.go)

kill "$POLLER_PID" 2>/dev/null || true
wait "$POLLER_PID" 2>/dev/null || true
trap - EXIT

# -----------------------------------------------------------------------------
# 4. Attach the poller output to the run directory
# -----------------------------------------------------------------------------
echo -e "${COLOR}[4/4] 💾 Saving unschedulable_bindings.jsonl into the run directory...${RESET}"
RUN_DIR="$(ls -td "$OUTPUT_DIR"/*/ 2>/dev/null | head -1 || true)"
if [ -n "$RUN_DIR" ] && [ "$(stat -c %Y "$RUN_DIR")" -ge "$((RUN_START_EPOCH - 60))" ]; then
  mv "$UNSCHED_TMP" "${RUN_DIR%/}/unschedulable_bindings.jsonl"
  # Timestamp of this run, for callers that chain the analyzer (make setup-and-start-baseline)
  basename "${RUN_DIR%/}" > "$OUTPUT_DIR/.last_baseline_run"
  echo -e "${COLOR}✅ Baseline run finished. Data in: ${RUN_DIR%/}${RESET}"
  echo -e "${COLOR}   Generate plots with: make -C analyzer generate-plots RUN_DIR=${RUN_DIR%/}${RESET}"
else
  echo -e "${COLOR}⚠️  Could not locate the run directory created by this run.${RESET}"
  echo -e "${COLOR}   Poller output kept at: $UNSCHED_TMP${RESET}"
  exit 1
fi
