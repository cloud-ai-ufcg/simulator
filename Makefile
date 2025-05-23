.PHONY: all setup_ai_engine run_simulator clean

PYTHON = python # Ou python3, dependendo do seu sistema

# Alvo padrão: configura o AI-Engine e depois roda o simulador
all: setup_ai_engine run_simulator

# Instala as dependências do AI-Engine
setup_ai_engine:
	@echo "Configurando dependências do AI-Engine..."
	@$(PYTHON) -m pip install -r ai-engine/requirements.txt
	@echo "Dependências do AI-Engine configuradas."

# Roda o simulador Go
run_simulator:
	@echo "Iniciando o Simulador Go..."
	@go run main.go
	@echo "Simulador Go finalizado."

# Limpa arquivos gerados (exemplo, pode ser expandido)
clean:
	@echo "Limpando arquivos gerados..."
	@rm -f monitor_output.json
	@rm -f ai-engine/actuator/recommendations.csv
	@rm -f ai-engine/engine/config.yaml
	# Adicione outros comandos de limpeza conforme necessário
	@echo "Limpeza concluída."

help:
	@echo "Available targets:"
	@echo "  all                  : Instala dependências do AI-Engine e roda o simulador"
	@echo "  setup_ai_engine      : Instala as dependências do AI-Engine (pip install)"
	@echo "  run_simulator        : Roda a aplicação principal do simulador (go run main.go)"
	@echo "  clean                : Remove arquivos gerados pelo simulador e AI-Engine"
	@echo "  help                 : Mostra esta mensagem de ajuda" 