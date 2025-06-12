SHELL := /bin/bash
.PHONY: all setup-and-start start setup-kubernetes-infra install-ai-deps help

# Default target: setups infrastructure and runs the simulator
all: setup-and-start

# Target to setup infrastructure (Kubernetes, AI-Engine dependencies) AND run the simulator
setup-and-start: setup-kubernetes-infra install-ai-deps start
	@echo -e "\\e[32mProcesso de configuração da infraestrutura completa e inicialização do simulador concluído.\\e[0m"

# Target to ONLY start the Go simulator (assumes infrastructure and dependencies are already set up)
start:
	@echo "Iniciando o Simulador Go..."
	@( \
		set -e; \
		_EFFECTIVE_HOME="$$HOME"; \
		echo "Initial HOME para execução do Go: $$_EFFECTIVE_HOME"; \
		if grep -qEi "(Microsoft|WSL)" /proc/version &> /dev/null ; then \
			echo "Ambiente detectado para execução do Go: WSL"; \
			_WIN_USER=$$(cmd.exe /c "echo %USERNAME%" 2>/dev/null | tr -d '\\r'); \
			if [ -z "$$_WIN_USER" ]; then \
				echo "Erro: Não foi possível detectar o usuário do Windows. Certifique-se de que o WSL está configurado corretamente."; \
				exit 1; \
			fi; \
			_EFFECTIVE_HOME="/mnt/c/Users/$$_WIN_USER"; \
			echo "HOME para esta sessão de execução do Go será: $$_EFFECTIVE_HOME"; \
		else \
			echo "Ambiente detectado para execução do Go: Linux normal. Usando HOME existente: $$_EFFECTIVE_HOME"; \
		fi; \
		\
		echo -e "\\e[36mIniciando o Simulador Go (usando HOME=$$_EFFECTIVE_HOME)...\\e[0m"; \
		HOME="$$_EFFECTIVE_HOME" go run main.go; \
		echo -e "\\e[36mSimulador Go finalizado.\\e[0m"; \
	)

# Target to setup the Kubernetes infrastructure using scripts/main.sh
setup-kubernetes-infra:
	@echo -e "\\e[35mIniciando configuração da infraestrutura Kubernetes (scripts/main.sh)...\\e[0m"
	@( \
		cd scripts && ./main.sh; \
	)
	@echo -e "\\e[35mConfiguração da infraestrutura Kubernetes concluída.\\e[0m"

# Target to install AI-Engine dependencies
install-ai-deps:
	@echo "Configurando dependências do AI-Engine..."
	@( \
		set -e; \
		_EFFECTIVE_HOME="$$HOME"; \
		echo "Initial HOME para instalação de dependências: $$_EFFECTIVE_HOME"; \
		if grep -qEi "(Microsoft|WSL)" /proc/version &> /dev/null ; then \
			echo "Ambiente detectado para instalação de dependências: WSL"; \
			_WIN_USER=$$(cmd.exe /c "echo %USERNAME%" 2>/dev/null | tr -d '\\r'); \
			if [ -z "$$_WIN_USER" ]; then \
				echo "Erro: Não foi possível detectar o usuário do Windows. Certifique-se de que o WSL está configurado corretamente."; \
				exit 1; \
			fi; \
			_EFFECTIVE_HOME="/mnt/c/Users/$$_WIN_USER"; \
			echo "HOME para esta sessão de instalação de dependências será: $$_EFFECTIVE_HOME"; \
		else \
			echo "Ambiente detectado para instalação de dependências: Linux normal. Usando HOME existente: $$_EFFECTIVE_HOME"; \
		fi; \
		\
		echo -e "\\e[32mInstalando dependências do AI-Engine (usando HOME=$$_EFFECTIVE_HOME)...\\e[0m"; \
		HOME="$$_EFFECTIVE_HOME" python3 -m pip install -r ai-engine/requirements.txt; \
		echo -e "\\e[32mDependências do AI-Engine configuradas com sucesso.\\e[0m"; \
	)

# To clean up (optional, but good practice)
# clean:
# @echo "Cleaning up..."
# Add cleanup commands here if needed, e.g., removing build artifacts or virtual environments.

help:
	@echo "Available targets:"
	@echo "  all                      : Alias para 'setup-and-start'."
	@echo "  setup-and-start          : Configura a infraestrutura Kubernetes, instala dependências do AI-Engine e inicia o simulador Go."
	@echo "  start                    : Inicia APENAS o simulador Go (assume que a infraestrutura e as dependências já estão configuradas)."
	@echo "  ---"
	@echo "  Individual setup steps (geralmente chamados por 'setup-and-start'):"
	@echo "    setup-kubernetes-infra : Executa scripts/main.sh para configurar a infraestrutura Kubernetes."
	@echo "    install-ai-deps      : Instala APENAS as dependências Python do AI-Engine."
	@echo "  ---"
	@echo "  help                     : Mostra esta mensagem de ajuda."