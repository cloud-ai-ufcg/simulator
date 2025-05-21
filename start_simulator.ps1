# Define a variável de ambiente HOME para o diretório do perfil do usuário atual
$env:HOME = $env:USERPROFILE

# Exibe uma mensagem informando que HOME foi definida (opcional, para feedback)
Write-Host "Variável de ambiente HOME definida como: $env:HOME"

# Executa o programa Go principal do simulador
Write-Host "Iniciando o simulador..."
go run main.go 