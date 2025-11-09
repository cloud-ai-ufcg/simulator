#!/bin/bash
# -----------------------------------------------------------------------------
# Update compose.yaml KWOK_MODE Environment Variable
# -----------------------------------------------------------------------------
# This script updates the KWOK_MODE environment variable in compose.yaml
# based on the execution mode (kwok or real)
# -----------------------------------------------------------------------------

set -euo pipefail

MODE="${1:-kwok}"

# Validate mode
if [[ "$MODE" != "kwok" ]] && [[ "$MODE" != "real" ]]; then
    echo "❌ Error: Invalid mode '${MODE}'"
    echo "   Usage: ./update-compose-mode.sh [kwok|real]"
    exit 1
fi

# Convert mode to boolean for KWOK_MODE
if [[ "$MODE" == "kwok" ]]; then
    KWOK_MODE="true"
else
    KWOK_MODE="false"
fi

# Get the project root directory (parent of scripts)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
COMPOSE_FILE="$PROJECT_ROOT/compose.yaml"

# Check if compose.yaml exists
if [[ ! -f "$COMPOSE_FILE" ]]; then
    echo "❌ Error: compose.yaml not found at $COMPOSE_FILE"
    exit 1
fi

echo "📝 Updating KWOK_MODE to: $KWOK_MODE (mode: $MODE)"

# Use sed to update KWOK_MODE in compose.yaml
# This handles both formats:
# - KWOK_MODE=true
# - KWOK_MODE: true
if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS requires empty string after -i
    sed -i '' "s/KWOK_MODE=.*/KWOK_MODE=$KWOK_MODE/" "$COMPOSE_FILE"
    sed -i '' "s/KWOK_MODE:.*/KWOK_MODE: $KWOK_MODE/" "$COMPOSE_FILE"
else
    # Linux
    sed -i "s/KWOK_MODE=.*/KWOK_MODE=$KWOK_MODE/" "$COMPOSE_FILE"
    sed -i "s/KWOK_MODE:.*/KWOK_MODE: $KWOK_MODE/" "$COMPOSE_FILE"
fi

echo "✅ compose.yaml updated successfully"
