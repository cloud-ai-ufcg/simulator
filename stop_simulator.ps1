# Attempt to find and stop simulator processes
Write-Host "Attempting to terminate simulator processes..."

# Heuristic to find the simulator process (executable 'main' or 'go' with 'main.go' in the title).
# 'go run' compiles to a temporary executable, making precise identification challenging.
$SimulatorProcesses = Get-Process | Where-Object { $_.ProcessName -eq "main" -or ($_.ProcessName -eq "go" -and $_.MainWindowTitle -match "main.go") }

if ($null -ne $SimulatorProcesses) {
    Write-Host "Simulator processes found:"
    $SimulatorProcesses | Select-Object Id, ProcessName, Path | Format-Table -AutoSize
    
    Write-Host "Terminating simulator processes..."
    try {
        Stop-Process -InputObject $SimulatorProcesses -Force -ErrorAction Stop
        Write-Host "Simulator processes terminated."
    } catch {
        Write-Warning "Error attempting to terminate processes: $($_.Exception.Message)"
    }
} else {
    Write-Host "No simulator processes found (based on current heuristic)."
}

Write-Host ""
Write-Host "Cleaning up Kubernetes resources (deployments and jobs in the default namespace)..."
kubectl delete deployment --all --namespace default
$LASTEXITCODE_DEPLOY = $LASTEXITCODE
kubectl delete job --all --namespace default
$LASTEXITCODE_JOB = $LASTEXITCODE

if ($LASTEXITCODE_DEPLOY -eq 0 -and $LASTEXITCODE_JOB -eq 0) {
  Write-Host "Kubernetes resources cleaned up successfully."
} else {
  Write-Warning "Attention: Error occurred while cleaning up Kubernetes resources."
  if ($LASTEXITCODE_DEPLOY -ne 0) {
    Write-Warning "  Error deleting deployments (exit code: $LASTEXITCODE_DEPLOY)"
  }
  if ($LASTEXITCODE_JOB -ne 0) {
    Write-Warning "  Error deleting jobs (exit code: $LASTEXITCODE_JOB)"
  }
  Write-Host "Manual cluster check may be required."
}

Write-Host ""
Write-Host "Shutdown and cleanup script finished." 