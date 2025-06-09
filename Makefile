SHELL := /bin/bash
.PHONY: all run

# Default target
all: run

# Target to run the simulator, including dependency installation and environment setup
run:
	@echo "Starting simulator process..."
	@( \
		set -e; \
		_EFFECTIVE_HOME="$$HOME"; \
		echo "Initial HOME: $$_EFFECTIVE_HOME"; \
		if grep -qEi "(Microsoft|WSL)" /proc/version &> /dev/null ; then \
			echo "Ambiente detectado: WSL"; \
			_WIN_USER=$$(cmd.exe /c "echo %USERNAME%" 2>/dev/null | tr -d '\\r'); \
			if [ -z "$$_WIN_USER" ]; then \
				echo "Erro: Não foi possível detectar o usuário do Windows. Certifique-se de que o WSL está configurado corretamente."; \
				exit 1; \
			fi; \
			_EFFECTIVE_HOME="/mnt/c/Users/$$_WIN_USER"; \
			echo "HOME for this session will be set to: $$_EFFECTIVE_HOME"; \
		else \
			echo "Ambiente detectado: Linux normal. Using existing HOME: $$_EFFECTIVE_HOME"; \
		fi; \
		\
		echo -e "\\e[32mConfigurando dependências do AI-Engine (using HOME=$$_EFFECTIVE_HOME)...\\e[0m"; \
		HOME="$$_EFFECTIVE_HOME" python3 -m pip install -r ai-engine/requirements.txt; \
		echo -e "\\e[32mDependências do AI-Engine configuradas com sucesso.\\e[0m"; \
		\
		echo -e "\\e[36mIniciando o Simulador Go (using HOME=$$_EFFECTIVE_HOME)...\\e[0m"; \
		HOME="$$_EFFECTIVE_HOME" go run main.go; \
		echo -e "\\e[36mSimulador Go finalizado.\\e[0m"; \
		echo -e "\\e[32mProcesso de inicialização completo.\\e[0m"; \
	)

# To clean up (optional, but good practice)
# clean:
# @echo "Cleaning up..."
# Add cleanup commands here if needed, e.g., removing build artifacts or virtual environments.

help:
	@echo "Available targets:"
	@echo "  all                  : Instala dependências do AI-Engine e roda o simulador"
	@echo "  run                  : Roda a aplicação principal do simulador (go run main.go)"
	@echo "  help                 : Mostra esta mensagem de ajuda"