# Tenta encontrar e parar processos do simulador
Write-Host "Tentando encerrar processos do simulador..."

# Heurística para encontrar o processo do simulador (executável 'main' ou 'go' com 'main.go' no título).
# 'go run' compila para um executável temporário, tornando a identificação precisa desafiadora.
$SimulatorProcesses = Get-Process | Where-Object { $_.ProcessName -eq "main" -or ($_.ProcessName -eq "go" -and $_.MainWindowTitle -match "main.go") }

if ($null -ne $SimulatorProcesses) {
    Write-Host "Processos do simulador encontrados:"
    $SimulatorProcesses | Select-Object Id, ProcessName, Path | Format-Table -AutoSize
    
    Write-Host "Encerrando processos do simulador..."
    try {
        Stop-Process -InputObject $SimulatorProcesses -Force -ErrorAction Stop
        Write-Host "Processos do simulador encerrados."
    } catch {
        Write-Warning "Erro ao tentar encerrar processos: $($_.Exception.Message)"
    }
} else {
    Write-Host "Nenhum processo do simulador encontrado (baseado na heurística atual)."
}

Write-Host ""
Write-Host "Limpando recursos do Kubernetes (deployments e jobs no namespace default)..."
kubectl delete deployment --all --namespace default
$LASTEXITCODE_DEPLOY = $LASTEXITCODE
kubectl delete job --all --namespace default
$LASTEXITCODE_JOB = $LASTEXITCODE

if ($LASTEXITCODE_DEPLOY -eq 0 -and $LASTEXITCODE_JOB -eq 0) {
  Write-Host "Recursos do Kubernetes limpos com sucesso."
} else {
  Write-Warning "Atenção: Erro ao limpar recursos do Kubernetes."
  if ($LASTEXITCODE_DEPLOY -ne 0) {
    Write-Warning "  Erro ao deletar deployments (código: $LASTEXITCODE_DEPLOY)"
  }
  if ($LASTEXITCODE_JOB -ne 0) {
    Write-Warning "  Erro ao deletar jobs (código: $LASTEXITCODE_JOB)"
  }
  Write-Host "Verifique o cluster manualmente."
}

Write-Host ""
Write-Host "Script de encerramento e limpeza concluído." 