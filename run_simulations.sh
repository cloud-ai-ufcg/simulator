#!/usr/bin/env bash

set -uo pipefail

# =============================================================================
# EDIT HERE for what runs when no CLI overrides are passed (--model / const|
# varia / v1|v2 on the command line still take priority over these when set).
# =============================================================================
MODELS_DEFAULT=("openai/gpt-5" "google/gemini-2.5-pro" "anthropic/claude-sonnet-4.5")
INPUTS_DEFAULT=("input_const.json" "input_varia.json")
TEMPERATURES_DEFAULT=(0 0.1 0.5 1)
GRAPH_VERSIONS_DEFAULT=("v1" "v2")
# =============================================================================

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${ROOT_DIR}/simulator/data/config.yaml"
BACKUP_FILE="${CONFIG_FILE}.auto_backup"
# make setup-and-start-auto runs under sudo, so the simulator writes each
# run's output directory as root. OWNER_USER is who non-sudo steps (copying
# config/input, running the analyzer) further down should own it as instead.
OWNER_USER="${SUDO_USER:-$USER}"
# sudo's secure_path (common default) overrides PATH even with -E, so under
# sudo "python3" can resolve to the system interpreter instead of this
# user's (e.g. Anaconda's), which is missing matplotlib/pandas and makes
# analyzer/Makefile's generate-plots fail silently (main.go only logs the
# error). Resolve it now, before sudo, and pass it through explicitly.
ANALYZER_PYTHON="$(command -v python3)"

if ! command -v yq >/dev/null 2>&1; then
  echo "Error: 'yq' not found in PATH. Please install yq (v4+) before running this script."
  exit 1
fi

if [ ! -f "${CONFIG_FILE}" ]; then
  echo "Error: configuration file not found at: ${CONFIG_FILE}"
  exit 1
fi

# CLI flags (order-independent) plus legacy positional filters, e.g.:
#   ./run_simulations.sh                                  # AI, all inputs, v1+v2
#   ./run_simulations.sh const v1                         # AI, input_const.json, v1
#   ./run_simulations.sh --scenario baseline --repeat 5   # baseline, 5x in a row
#   ./run_simulations.sh --model openai/gpt-5 --repeat 5  # AI, gpt-5 only, 5x in a row
SCENARIO="ai"
REPEAT=1
MODEL_FILTER=""
POSITIONAL=()
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help)
      script_name="$(basename "$0")"
      cat <<EOF
Usage: ${script_name} [OPTIONS] [INPUT_FILTER] [GRAPH_VERSION]

OPTIONS:
  --scenario ai|baseline   Which flow to run (default: ai)
  --repeat N               Repeat the whole matrix N times in a row, same
                            infra cleanup between runs as a single run
                            (default: 1)
  --model MODEL            Restrict the ai scenario to a single model
                            (ignored for baseline)

INPUT_FILTER (positional):
  (none)       Run both input_const.json and input_varia.json
  const        Run only input_const.json (24 nodes/cluster)
  varia        Run only input_varia.json (38 nodes/cluster)

GRAPH_VERSION (positional, ai scenario only):
  (none)       Run both v1 and v2
  v1           Use only graph version v1
  v2           Use only graph version v2

Examples:
  ${script_name}                                       # AI, all inputs, v1 and v2
  ${script_name} const                                 # AI, only input_const.json, v1 and v2
  ${script_name} varia v1                               # AI, only input_varia.json, graph v1
  ${script_name} --scenario baseline --repeat 5         # baseline, 5x in a row, both inputs
  ${script_name} --scenario baseline --repeat 5 const   # baseline, 5x in a row, input_const.json only
  ${script_name} --model openai/gpt-5 --repeat 5        # AI, gpt-5 only, 5x in a row
EOF
      exit 0
      ;;
    --scenario)
      [ $# -ge 2 ] || { echo "Missing value for --scenario"; exit 1; }
      SCENARIO="$2"; shift 2
      ;;
    --repeat)
      [ $# -ge 2 ] || { echo "Missing value for --repeat"; exit 1; }
      REPEAT="$2"; shift 2
      ;;
    --model)
      [ $# -ge 2 ] || { echo "Missing value for --model"; exit 1; }
      MODEL_FILTER="$2"; shift 2
      ;;
    *)
      POSITIONAL+=("$1"); shift
      ;;
  esac
done

case "${SCENARIO}" in
  ai|baseline) ;;
  *)
    echo "Invalid --scenario: '${SCENARIO}'. Use 'ai' or 'baseline'."
    exit 1
    ;;
esac

if ! [[ "${REPEAT}" =~ ^[0-9]+$ ]] || [ "${REPEAT}" -lt 1 ]; then
  echo "Invalid --repeat: '${REPEAT}'. Use a positive integer."
  exit 1
fi

INPUT_FILTER="${POSITIONAL[0]-}"
GRAPH_FILTER="${POSITIONAL[1]-}"

echo "Checking sudo credentials (you may be prompted once)..."
if ! sudo -v; then
  echo "Error: failed to obtain sudo credentials."
  exit 1
fi

# Keep sudo credentials alive while the script runs
(
  while true; do
    sudo -n true >/dev/null 2>&1 || exit 0
    sleep 60
  done
) &
SUDO_KEEPALIVE_PID=$!

cleanup() {
  if [ -n "${SUDO_KEEPALIVE_PID:-}" ]; then
    kill "${SUDO_KEEPALIVE_PID}" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

echo "Creating configuration backup at: ${BACKUP_FILE}"
cp "${CONFIG_FILE}" "${BACKUP_FILE}"

# Parameter combinations (defaults edited above, at the top of the file)
if [ "${SCENARIO}" = "baseline" ]; then
  # Baseline has no AI model/graph/temperature axes.
  MODELS=("-")
  TEMPERATURES=("-")
  GRAPH_VERSIONS=("-")
else
  MODELS=("${MODELS_DEFAULT[@]}")
  if [ -n "${MODEL_FILTER}" ]; then
    MODELS=("${MODEL_FILTER}")
  fi
  TEMPERATURES=("${TEMPERATURES_DEFAULT[@]}")
  GRAPH_VERSIONS=("${GRAPH_VERSIONS_DEFAULT[@]}")
fi
INPUTS=("${INPUTS_DEFAULT[@]}")

# Filter by input type (const/varia)
case "${INPUT_FILTER}" in
  "" )
    # No filter: keep both inputs
    ;;
  const)
    INPUTS=("input_const.json")
    ;;
  varia)
    INPUTS=("input_varia.json")
    ;;
  *)
    echo "Invalid input type: '${INPUT_FILTER}'"
    echo "Usage: $0 [OPTIONS] [const|varia] [v1|v2]"
    exit 1
    ;;
esac

# Optional filter by graph version (ai scenario only)
if [ "${SCENARIO}" = "ai" ]; then
  case "${GRAPH_FILTER}" in
    "" )
      # No filter: keep both versions
      ;;
    v1)
      GRAPH_VERSIONS=("v1")
      ;;
    v2)
      GRAPH_VERSIONS=("v2")
      ;;
    *)
      echo "Invalid graph_version: '${GRAPH_FILTER}'. Use 'v1' or 'v2'."
      exit 1
      ;;
  esac
elif [ -n "${GRAPH_FILTER}" ]; then
  echo "Warning: graph_version '${GRAPH_FILTER}' ignored (baseline has no graph versions)."
fi

run_counter=0
declare -a RUN_STATUS
declare -a RUN_DESC

for model in "${MODELS[@]}"; do
  for input_file in "${INPUTS[@]}"; do
    for temp in "${TEMPERATURES[@]}"; do
      for graph in "${GRAPH_VERSIONS[@]}"; do
        echo "============================================"
        echo "Combination:"
        echo "  scenario        = ${SCENARIO}"
        if [ "${SCENARIO}" = "ai" ]; then
          echo "  model           = ${model}"
          echo "  temperature     = ${temp}"
          echo "  graph_version   = ${graph}"
        fi
        echo "  input_json      = ${input_file}"
        echo "  repeat          = ${REPEAT}"
        echo "============================================"

        # Restore original config before applying changes
        cp "${BACKUP_FILE}" "${CONFIG_FILE}"

        if [ "${SCENARIO}" = "ai" ]; then
          # Update AI engine parameters in config.yaml
          yq -i '.["ai-engine"].ai.selected_model = "'"${model}"'"' "${CONFIG_FILE}"
          yq -i '.["ai-engine"].data.input_json = "'"${input_file}"'"' "${CONFIG_FILE}"
          yq -i '.["ai-engine"].ai.multi_agent.graph_version = "'"${graph}"'"' "${CONFIG_FILE}"
          yq -i '.["ai-engine"].ai.multi_agent.generation_config.temperature = '"${temp}" "${CONFIG_FILE}"
        fi

        # Adjust cluster size (nodes per member) based on the selected input file
        # - input_const.json  -> 24 nodes per cluster
        # - input_varia.json  -> 38 nodes per cluster
        nodes_value=38
        case "${input_file}" in
          input_const.json)
            nodes_value=24
            ;;
          input_varia.json)
            nodes_value=38
            ;;
        esac
        yq -i ".clusters.member1.nodes = ${nodes_value}" "${CONFIG_FILE}"
        yq -i ".clusters.member2.nodes = ${nodes_value}" "${CONFIG_FILE}"

        echo "Configuration applied to ${CONFIG_FILE}."

        # Ensure simulator uses the same input file as configured for the AI engine
        SIM_INPUT_SRC="${ROOT_DIR}/simulator/data/${input_file}"
        SIM_INPUT_DST="${ROOT_DIR}/simulator/data/input.json"
        if [ -f "${SIM_INPUT_SRC}" ]; then
          echo "Syncing simulator input: ${SIM_INPUT_SRC} -> ${SIM_INPUT_DST}"
          cp "${SIM_INPUT_SRC}" "${SIM_INPUT_DST}"
        else
          echo "Warning: simulator input source file not found: ${SIM_INPUT_SRC}"
        fi

        MAKE_TARGET="setup-and-start-auto"
        if [ "${SCENARIO}" = "baseline" ]; then
          MAKE_TARGET="setup-and-start-baseline"
        fi

        # Repeats run the same full make target back to back — each one
        # already tears down and rebuilds the infra from scratch (stop-*
        # -> setup-* -> run-all-containers-*), so the environment is just
        # as clean between repeats as it is between distinct combinations.
        for rep in $(seq 1 "${REPEAT}"); do
          run_counter=$((run_counter + 1))

          if [ "${SCENARIO}" = "ai" ]; then
            desc="Scenario=ai | Model=${model} | Input=${input_file} | Temp=${temp} | Graph=${graph} | Rep=${rep}/${REPEAT}"
          else
            desc="Scenario=baseline | Input=${input_file} | Rep=${rep}/${REPEAT}"
          fi
          status="SUCCESS"

          echo "--------------------------------------------"
          echo "Simulation ${run_counter} (repeat ${rep}/${REPEAT}): ${desc}"

          echo "Running: make ${MAKE_TARGET} (this may take a while)..."
          if ! (cd "${ROOT_DIR}" && sudo -E ANALYZER_PYTHON="${ANALYZER_PYTHON}" make "${MAKE_TARGET}"); then
            echo "❌ Failed to execute make ${MAKE_TARGET}."
            status="FAILED (${MAKE_TARGET})"
          else
            echo "Finding latest output directory in simulator/data/output..."
            LAST_RUN_DIR="$(ls -1dt "${ROOT_DIR}/simulator/data/output"/*/ 2>/dev/null | head -1 || true)"
            if [ -z "${LAST_RUN_DIR}" ]; then
              echo "Warning: no output directory found in simulator/data/output. Skipping plot generation."
              status="FAILED (no output)"
            else
              TIMESTAMP="$(basename "${LAST_RUN_DIR}")"
              echo "Latest simulation detected: ${TIMESTAMP}"

              # The run directory was just created by the sudo'd simulator, so
              # it's root-owned. Reclaim it now (not just at the very end) so
              # the plain (non-sudo) cp/analyzer steps below can write into it.
              echo "Fixing ownership of ${LAST_RUN_DIR} for user: ${OWNER_USER}..."
              if ! sudo chown -R "${OWNER_USER}:${OWNER_USER}" "${LAST_RUN_DIR%/}"; then
                echo "Warning: failed to chown ${LAST_RUN_DIR} to ${OWNER_USER}."
              fi

              echo "Copying config and input used to ${LAST_RUN_DIR}..."
              if ! cp "${CONFIG_FILE}" "${LAST_RUN_DIR%/}/config_used.yaml"; then
                echo "Warning: failed to copy config file to ${LAST_RUN_DIR}."
              fi
              if ! cp "${ROOT_DIR}/simulator/data/${input_file}" "${LAST_RUN_DIR%/}/input_used.json"; then
                echo "Warning: failed to copy input file to ${LAST_RUN_DIR}."
              fi

              # Rename the simulator output directory (and everything the
              # analyzer just wrote inside it) to a descriptive name. A repeat
              # suffix is only added when repeating (REPEAT > 1), so a plain
              # single run keeps the exact same naming as before.
              input_base="$(basename "${input_file}" .json)"
              if [ "${SCENARIO}" = "baseline" ]; then
                new_name="baseline_${input_base}"
              else
                safe_model="${model//\//-}"
                safe_model="${safe_model// /_}"
                new_name="${safe_model}_${input_base}_${graph}_${temp}"
              fi
              if [ "${REPEAT}" -gt 1 ]; then
                new_name="${new_name}_rep${rep}"
              fi

              old_sim_dir="${LAST_RUN_DIR%/}"
              new_sim_dir="${ROOT_DIR}/simulator/data/output/${new_name}"

              echo "Renaming simulator output directory to: ${new_sim_dir}"
              if [ -d "${old_sim_dir}" ] && [ "${old_sim_dir}" != "${new_sim_dir}" ]; then
                if ! sudo mv "${old_sim_dir}" "${new_sim_dir}"; then
                  echo "Warning: failed to rename simulator output directory from ${old_sim_dir} to ${new_sim_dir}."
                else
                  LAST_RUN_DIR="${new_sim_dir}/"
                fi
              fi
            fi
          fi

          RUN_STATUS[run_counter]="${status}"
          RUN_DESC[run_counter]="${desc}"

          echo "Simulation ${run_counter} finished with status: ${status}."
          echo
        done
      done
    done
  done
done

echo "Restoring original configuration at ${CONFIG_FILE}."
cp "${BACKUP_FILE}" "${CONFIG_FILE}"

echo "============================================"
echo "Simulations summary:"
echo "  Total: ${run_counter}"

success_count=0
fail_count=0
if [ "${run_counter}" -gt 0 ]; then
  for i in $(seq 1 "${run_counter}"); do
    if [[ "${RUN_STATUS[i]}" == "SUCCESS" ]]; then
      success_count=$((success_count + 1))
    else
      fail_count=$((fail_count + 1))
    fi
  done
fi

echo "  Success: ${success_count}"
echo "  Failed:  ${fail_count}"
echo "--------------------------------------------"
echo "Details:"
if [ "${run_counter}" -gt 0 ]; then
  for i in $(seq 1 "${run_counter}"); do
    echo "  ${i}. ${RUN_STATUS[i]} | ${RUN_DESC[i]}"
  done
else
  echo "  No simulations were executed."
fi
echo "============================================"

# Final sweep, in case any run directory was missed above (e.g. the
# generate-plots step failed before reaching its own chown, or a run's
# status was FAILED before that point) — ensures nothing is left root-owned.
if [ -n "${OWNER_USER}" ]; then
  echo "Fixing ownership of output directories for user: ${OWNER_USER}"
  if [ -d "${ROOT_DIR}/simulator/data/output" ]; then
    sudo chown -R "${OWNER_USER}:${OWNER_USER}" "${ROOT_DIR}/simulator/data/output" || true
  fi
  if [ -d "${ROOT_DIR}/analyzer/output" ]; then
    sudo chown -R "${OWNER_USER}:${OWNER_USER}" "${ROOT_DIR}/analyzer/output" || true
  fi
fi

echo "All simulations finished."
echo "You can find outputs in: ${ROOT_DIR}/simulator/data/output/"
