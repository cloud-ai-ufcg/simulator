#!/usr/bin/env bash
# portfw.sh – port-forward automático de Prometheus, SEM tmux
# Requisitos: bash 4+, kubectl

declare -A CLUSTERS=(
  [member1]=9090   # context no kubeconfig → porta em localhost
  [member2]=9091
)

NAMESPACE="default"
SERVICE="prometheus-server"
SERVICE_PORT=80

# Flag to control the loop
RUNNING=true

# Handle SIGTERM
trap 'RUNNING=false' SIGTERM SIGINT

port_forward_loop() {
  local ctx=$1
  local host_port=$2

  while $RUNNING; do
    echo "[$(date +%T)] $ctx → localhost:$host_port  (iniciando)"
    kubectl --context "$ctx" -n "$NAMESPACE" \
            port-forward "svc/$SERVICE" "$host_port:$SERVICE_PORT" \
            --address 127.0.0.1 \
            2>&1 | sed -e "s/^/[$ctx] /"

    if ! $RUNNING; then
      echo "[$(date +%T)] $ctx stopping gracefully..."
      break
    fi

    echo "[$(date +%T)] $ctx caiu, tentando reconectar em 2 s…" >&2
    sleep 2
  done
}

########################################
# 3. Lança um loop por cluster
########################################
declare -a PIDS=()

for CTX in "${!CLUSTERS[@]}"; do
  PORT="${CLUSTERS[$CTX]}"

  # Verifica se o contexto existe
  if ! kubectl config get-contexts "$CTX" &>/dev/null; then
    echo "⚠️  Contexto '$CTX' não existe — ignorando."
    continue
  fi

  # Inicia em subshell + background
  port_forward_loop "$CTX" "$PORT" &
  PIDS+=($!)          # guarda PID para matar depois
done

if [[ ${#PIDS[@]} -eq 0 ]]; then
  echo "Nenhum port-forward iniciado. Revise o array CLUSTERS."
  exit 1
fi

########################################
# 4. Trap p/ encerrar tudo com Ctrl-C
########################################
trap 'echo -e "\nEncerrando..."; RUNNING=false; wait; exit' SIGINT SIGTERM

echo "Pressione Ctrl-C para parar."
wait                          # bloqueia aqui enquanto os loops rodam

