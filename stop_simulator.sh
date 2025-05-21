#!/bin/bash

echo "Attempting to terminate local simulator processes ('go run main.go')..."

# pgrep -f compares the pattern against the full command line.
PIDS=$(pgrep -f "go run main.go")

if [ -z "$PIDS" ]; then
  echo "No local simulator processes found."
else
  echo "Local processes found with PIDs: $PIDS. Attempting SIGTERM..."
  kill -SIGTERM $PIDS # No quotes around $PIDS for kill

  sleep 2 # Wait for graceful shutdown.

  ALIVE_PIDS=""
  for pid_to_check in $PIDS; do
    # Check if process is still alive
    if ps -p $pid_to_check > /dev/null; then
      ALIVE_PIDS="$ALIVE_PIDS $pid_to_check"
    fi
  done

  if [ -n "$ALIVE_PIDS" ]; then
    echo "Processes (PIDs:$ALIVE_PIDS) still active. Attempting SIGKILL..."
    kill -SIGKILL $ALIVE_PIDS # No quotes around $ALIVE_PIDS for kill
    echo "Local processes forced to terminate."
  else
    echo "Local processes terminated with SIGTERM."
  fi
fi

echo ""
echo "Cleaning up Kubernetes resources (deployments and jobs in the default namespace)..."
kubectl delete deployment --all --namespace default && kubectl delete job --all --namespace default

KUBECTL_EXIT_CODE=$?
if [ $KUBECTL_EXIT_CODE -eq 0 ]; then
  echo "Kubernetes resources cleaned up successfully."
else
  echo "Attention: Error cleaning up Kubernetes resources (exit code: $KUBECTL_EXIT_CODE). Check cluster manually."
fi

echo ""
echo "Shutdown and cleanup script finished." 