#!/bin/bash

echo "Tentando encerrar processos locais do simulador ('go run main.go')..."

# pgrep -f compara o padrão com toda a linha de comando.
PIDS=$(pgrep -f "go run main.go")

if [ -z "$PIDS" ]; then
  echo "Nenhum processo local do simulador encontrado."
else
  echo "Processos locais encontrados com PIDs: $PIDS. Tentando SIGTERM..."
  kill -SIGTERM $PIDS

  sleep 2 # Aguarda encerramento gracioso.

  ALIVE_PIDS=""
  for pid_to_check in $PIDS; do
    if ps -p $pid_to_check > /dev/null; then
      ALIVE_PIDS="$ALIVE_PIDS $pid_to_check"
    fi
  done

  if [ -n "$ALIVE_PIDS" ]; then
    echo "Processos (PIDs:$ALIVE_PIDS) ainda ativos. Tentando SIGKILL..."
    kill -SIGKILL $ALIVE_PIDS
    echo "Processos locais forçados a encerrar."
  else
    echo "Processos locais encerrados com SIGTERM."
  fi
fi

echo ""
echo "Limpando recursos do Kubernetes (deployments e jobs no namespace default)..."
kubectl delete deployment --all --namespace default && kubectl delete job --all --namespace default

KUBECTL_EXIT_CODE=$?
if [ $KUBECTL_EXIT_CODE -eq 0 ]; then
  echo "Recursos do Kubernetes limpos com sucesso."
else
  echo "Atenção: Erro ao limpar recursos do Kubernetes (código de saída: $KUBECTL_EXIT_CODE). Verifique o cluster manualmente."
fi

echo ""
echo "Script de encerramento e limpeza concluído." 