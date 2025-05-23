# Set the HOME environment variable to the current user's profile directory, crucial for the broker.
$env:HOME = $env:USERPROFILE

# Display a message indicating that HOME has been set (optional, for feedback)
Write-Host "HOME environment variable set to: $env:HOME"

# Script para configurar o ambiente e iniciar o simulador

Write-Host "Configurando dependências do AI-Engine..." -ForegroundColor Green
python -m pip install -r ai-engine/requirements.txt
if ($LASTEXITCODE -ne 0) {
    Write-Host "Falha ao instalar dependências do AI-Engine. Verifique o output acima." -ForegroundColor Red
    exit 1
}
Write-Host "Dependências do AI-Engine configuradas com sucesso." -ForegroundColor Green

Write-Host "Iniciando o Simulador Go..." -ForegroundColor Cyan
go run main.go
if ($LASTEXITCODE -ne 0) {
    Write-Host "Falha ao executar o simulador Go. Verifique o output acima." -ForegroundColor Red
    exit 1
}

Write-Host "Simulador Go finalizado." -ForegroundColor Cyan
Write-Host "Processo de inicialização completo." -ForegroundColor Green 