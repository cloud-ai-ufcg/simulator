#!/bin/bash
# -----------------------------------------------------------------------------
# Mode Setup Helper – easily switch between KWOK and Real modes
# -----------------------------------------------------------------------------

if [ -z "$1" ]; then
    echo "Usage: ./setup-mode.sh [kwok|real]"
    echo ""
    echo "Current mode:"
    if [ -f "mode.env" ]; then
        grep EXECUTION_MODE mode.env | cut -d '=' -f2 | tr -d '"'
    else
        echo "  Not set (defaults to kwok)"
    fi
    exit 1
fi

MODE=$1

if [ "$MODE" != "kwok" ] && [ "$MODE" != "real" ]; then
    echo "❌ Error: Mode must be 'kwok' or 'real'"
    exit 1
fi

# Update mode.env
cat > mode.env <<EOF
# Execution Mode Configuration
# Options: "kwok" (simulated) or "real" (real workloads)
EXECUTION_MODE="$MODE"

# Real clusters configuration (only used when MODE=real)
REAL_CLUSTERS_ENABLED=$([ "$MODE" == "real" ] && echo "true" || echo "false")

# KWOK configuration (only used when MODE=kwok)
KWOK_ENABLED=$([ "$MODE" == "kwok" ] && echo "true" || echo "false")
EOF

echo "✅ Mode set to: $MODE"
echo ""
echo "Next steps:"
if [ "$MODE" == "kwok" ]; then
    echo "  1. Run: cd scripts && ./main.sh"
    echo "  2. This will setup simulated nodes via KWOK"
elif [ "$MODE" == "real" ]; then
    echo "  1. Ensure real clusters are configured and accessible"
    echo "  2. Run: cd scripts && ./main.sh"
    echo "  3. This will use your real Kubernetes nodes"
fi
