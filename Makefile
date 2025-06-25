SHELL := /bin/bash

# Variáveis globais
ACTUATOR_CONTAINER_NAME := actuator-simulator
ACTUATOR_IMAGE_NAME := actuator-api
ACTUATOR_DIR := actuator
ACTUATOR_DOCKERFILE := Dockerfile.api

BROKER_CONTAINER_NAME := broker-simulator
BROKER_IMAGE_NAME := broker:latest
BROKER_DIR := broker
BROKER_DOCKERFILE := Dockerfile.api

MONITOR_CONTAINER_NAME := monitor-simulator
MONITOR_IMAGE_NAME := monitor:latest
MONITOR_DIR := monitor

AI_ENGINE_CONTAINER_NAME := ai-engine-simulator
AI_ENGINE_IMAGE_NAME := ai-engine-api
AI_ENGINE_DIR := ai-engine

.PHONY: all setup-and-start start setup-kubernetes-infra \
        start-broker-container start-actuator-container start-monitor-container start-ai-engine-container stop-all-containers help

# Alvo padrão: configura infraestrutura e executa o simulador
all: setup-and-start

# Configura infraestrutura completa e executa o simulador
setup-and-start: setup-kubernetes-infra start-broker-container start-actuator-container start-monitor-container start-ai-engine-container start
	@echo -e "\\e[32mProcesso de configuração da infraestrutura completa e inicialização do simulador concluído.\\e[0m"

# Sobe o container do Broker se não estiver rodando
start-broker-container:
	@echo "Verificando se o container $(BROKER_CONTAINER_NAME) já está rodando..."
	@container_id_check=$$(sudo docker ps -q -f name=$(BROKER_CONTAINER_NAME)); \
	if [ -n "$$container_id_check" ]; then \
		echo "INFO: O container $(BROKER_CONTAINER_NAME) (ID: $$container_id_check) já está rodando."; \
	else \
		echo "INFO: O container $(BROKER_CONTAINER_NAME) não está rodando. Prosseguindo com a inicialização..."; \
		echo "Limpando container antigo (se existir)..."; \
		sudo docker stop $(BROKER_CONTAINER_NAME) >/dev/null 2>&1 || true; \
		sudo docker rm $(BROKER_CONTAINER_NAME) >/dev/null 2>&1 || true; \
		if ! sudo docker image inspect $(BROKER_IMAGE_NAME) > /dev/null 2>&1; then \
			echo "Construindo imagem $(BROKER_IMAGE_NAME) a partir de $(BROKER_DIR)/$(BROKER_DOCKERFILE)..."; \
			if [ ! -f $(BROKER_DIR)/$(BROKER_DOCKERFILE) ]; then \
				echo "ERRO: $(BROKER_DIR)/$(BROKER_DOCKERFILE) não encontrado! Impossível construir a imagem $(BROKER_IMAGE_NAME)."; \
				exit 2; \
			fi; \
			sudo docker build -t $(BROKER_IMAGE_NAME) -f $(BROKER_DIR)/$(BROKER_DOCKERFILE) $(BROKER_DIR) || { \
				echo "ERRO: Falha ao construir a imagem $(BROKER_IMAGE_NAME). Verifique o erro do build acima."; \
				exit 3; \
			}; \
		fi; \
		echo "Iniciando container $(BROKER_CONTAINER_NAME) a partir da imagem $(BROKER_IMAGE_NAME)..."; \
		sudo docker run -d --rm \
			--name $(BROKER_CONTAINER_NAME) \
			--network host \
			-p 8080:80 \
			-v $$HOME/.kube/karmada.config:/root/.kube/karmada.config \
			$(BROKER_IMAGE_NAME); \
		echo "Verificando o status do container $(BROKER_CONTAINER_NAME)..."; \
		sleep 2; \
		new_container_id=$$(sudo docker ps -q -f name=$(BROKER_CONTAINER_NAME)); \
		if [ -n "$$new_container_id" ]; then \
			echo "SUCESSO: O container $(BROKER_CONTAINER_NAME) (ID: $$new_container_id) está rodando."; \
		else \
			echo "ERRO: O container $(BROKER_CONTAINER_NAME) não iniciou corretamente após a tentativa."; \
			echo "Verifique os logs do Docker com: sudo docker logs $(BROKER_CONTAINER_NAME)"; \
			exit 1; \
		fi; \
		echo "Verificação do container $(BROKER_CONTAINER_NAME) concluída."; \
	fi

# Sobe o container do Actuator se não estiver rodando
start-actuator-container:
	@echo "Verificando se o container $(ACTUATOR_CONTAINER_NAME) já está rodando..."
	@container_id_check=$$(sudo docker ps -q -f name=$(ACTUATOR_CONTAINER_NAME)); \
	if [ -n "$$container_id_check" ]; then \
		echo "INFO: O container $(ACTUATOR_CONTAINER_NAME) (ID: $$container_id_check) já está rodando."; \
	else \
		echo "INFO: O container $(ACTUATOR_CONTAINER_NAME) não está rodando. Prosseguindo com a inicialização..."; \
		echo "Limpando container antigo (se existir)..."; \
		sudo docker stop $(ACTUATOR_CONTAINER_NAME) >/dev/null 2>&1 || true; \
		sudo docker rm $(ACTUATOR_CONTAINER_NAME) >/dev/null 2>&1 || true; \
		echo "Construindo imagem $(ACTUATOR_IMAGE_NAME) a partir de $(ACTUATOR_DIR)/$(ACTUATOR_DOCKERFILE)..."; \
		sudo docker build -t $(ACTUATOR_IMAGE_NAME) -f $(ACTUATOR_DIR)/$(ACTUATOR_DOCKERFILE) $(ACTUATOR_DIR); \
		echo "Iniciando container $(ACTUATOR_CONTAINER_NAME) a partir da imagem $(ACTUATOR_IMAGE_NAME)..."; \
		sudo docker run -d --rm \
			--name $(ACTUATOR_CONTAINER_NAME) \
			--network host \
			-v $$HOME/.kube/karmada.config:/root/.kube/config \
			-v $$HOME/.kwok:/home/$$USER/.kwok \
			$(ACTUATOR_IMAGE_NAME); \
		echo "Verificando o status do container $(ACTUATOR_CONTAINER_NAME)..."; \
		sleep 2; \
		new_container_id=$$(sudo docker ps -q -f name=$(ACTUATOR_CONTAINER_NAME)); \
		if [ -n "$$new_container_id" ]; then \
			echo "SUCESSO: O container $(ACTUATOR_CONTAINER_NAME) (ID: $$new_container_id) está rodando."; \
		else \
			echo "ERRO: O container $(ACTUATOR_CONTAINER_NAME) não iniciou corretamente após a tentativa."; \
			echo "Verifique os logs do Docker com: sudo docker logs $(ACTUATOR_CONTAINER_NAME)"; \
			exit 1; \
		fi; \
		echo "Verificação do container $(ACTUATOR_CONTAINER_NAME) concluída."; \
	fi

# Sobe o container do Monitor se não estiver rodando
start-monitor-container:
	@echo "Verificando se o container $(MONITOR_CONTAINER_NAME) já está rodando..."
	@container_id_check=$$(sudo docker ps -q -f name=$(MONITOR_CONTAINER_NAME)); \
	if [ -n "$$container_id_check" ]; then \
		echo "INFO: O container $(MONITOR_CONTAINER_NAME) (ID: $$container_id_check) já está rodando."; \
	else \
		echo "INFO: O container $(MONITOR_CONTAINER_NAME) não está rodando. Prosseguindo com a inicialização..."; \
		echo "Limpando container antigo (se existir)..."; \
		sudo docker stop $(MONITOR_CONTAINER_NAME) >/dev/null 2>&1 || true; \
		sudo docker rm $(MONITOR_CONTAINER_NAME) >/dev/null 2>&1 || true; \
		if ! sudo docker image inspect $(MONITOR_IMAGE_NAME) > /dev/null 2>&1; then \
			echo "Construindo imagem $(MONITOR_IMAGE_NAME) a partir de $(MONITOR_DIR)..."; \
			sudo docker build -t $(MONITOR_IMAGE_NAME) $(MONITOR_DIR) || { \
				echo "ERRO: Falha ao construir a imagem $(MONITOR_IMAGE_NAME). Verifique o erro do build acima."; \
				exit 3; \
			}; \
		fi; \
		echo "Iniciando container $(MONITOR_CONTAINER_NAME) a partir da imagem $(MONITOR_IMAGE_NAME)..."; \
		sudo docker run -d --rm \
			--name $(MONITOR_CONTAINER_NAME) \
			--network host \
			$(MONITOR_IMAGE_NAME); \
		echo "Verificando o status do container $(MONITOR_CONTAINER_NAME)..."; \
		sleep 2; \
		new_container_id=$$(sudo docker ps -q -f name=$(MONITOR_CONTAINER_NAME)); \
		if [ -n "$$new_container_id" ]; then \
			echo "SUCESSO: O container $(MONITOR_CONTAINER_NAME) (ID: $$new_container_id) está rodando."; \
		else \
			echo "ERRO: O container $(MONITOR_CONTAINER_NAME) não iniciou corretamente após a tentativa."; \
			echo "Verifique os logs do Docker com: sudo docker logs $(MONITOR_CONTAINER_NAME)"; \
			exit 1; \
		fi; \
		echo "Verificação do container $(MONITOR_CONTAINER_NAME) concluída."; \
	fi

# Sobe o container do AI-Engine se não estiver rodando
start-ai-engine-container:
	@echo "Verificando se o container $(AI_ENGINE_CONTAINER_NAME) já está rodando..."
	@container_id_check=$$(sudo docker ps -q -f name=$(AI_ENGINE_CONTAINER_NAME)); \
	if [ -n "$$container_id_check" ]; then \
		echo "INFO: O container $(AI_ENGINE_CONTAINER_NAME) (ID: $$container_id_check) já está rodando."; \
	else \
		echo "INFO: O container $(AI_ENGINE_CONTAINER_NAME) não está rodando. Prosseguindo com a inicialização..."; \
		echo "Limpando container antigo (se existir)..."; \
		sudo docker stop $(AI_ENGINE_CONTAINER_NAME) >/dev/null 2>&1 || true; \
		sudo docker rm $(AI_ENGINE_CONTAINER_NAME) >/dev/null 2>&1 || true; \
		echo "Construindo imagem $(AI_ENGINE_IMAGE_NAME) a partir de $(AI_ENGINE_DIR)..."; \
		sudo docker build -t $(AI_ENGINE_IMAGE_NAME) -f $(AI_ENGINE_DIR)/Dockerfile.api $(AI_ENGINE_DIR); \
		echo "Iniciando container $(AI_ENGINE_CONTAINER_NAME) a partir da imagem $(AI_ENGINE_IMAGE_NAME)..."; \
		sudo docker run -d --rm \
			--name $(AI_ENGINE_CONTAINER_NAME) \
			--network host \
			-p 8083:8083 \
			$(AI_ENGINE_IMAGE_NAME); \
		echo "Verificando o status do container $(AI_ENGINE_CONTAINER_NAME)..."; \
		sleep 2; \
		new_container_id=$$(sudo docker ps -q -f name=$(AI_ENGINE_CONTAINER_NAME)); \
		if [ -n "$$new_container_id" ]; then \
			echo "SUCESSO: O container $(AI_ENGINE_CONTAINER_NAME) (ID: $$new_container_id) está rodando."; \
		else \
			echo "ERRO: O container $(AI_ENGINE_CONTAINER_NAME) não iniciou corretamente após a tentativa."; \
			echo "Verifique os logs do Docker com: sudo docker logs $(AI_ENGINE_CONTAINER_NAME)"; \
			exit 1; \
		fi; \
		echo "Verificação do container $(AI_ENGINE_CONTAINER_NAME) concluída."; \
	fi

# Inicia apenas o simulador Go (infraestrutura já deve estar pronta)
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
		echo -e "\\e[36mIniciando o Simulador Go (usando HOME=$$_EFFECTIVE_HOME)...\\e[0m"; \
		HOME="$$_EFFECTIVE_HOME" go run main.go; \
		echo -e "\\e[36mSimulador Go finalizado.\\e[0m"; \
	)

# Configura infraestrutura Kubernetes
setup-kubernetes-infra:
	@echo -e "\\e[35mIniciando configuração da infraestrutura Kubernetes (scripts/main.sh)...\\e[0m"
	@( \
		cd scripts && ./main.sh; \
	)
	@echo -e "\\e[35mConfiguração da infraestrutura Kubernetes concluída.\\e[0m"


# Para e remove containers do Actuator e Broker
stop-all-containers:
	@echo "Tentando parar e remover o container $(ACTUATOR_CONTAINER_NAME)..."
	@sudo docker stop $(ACTUATOR_CONTAINER_NAME) >/dev/null 2>&1 || true
	@sudo docker rm $(ACTUATOR_CONTAINER_NAME) >/dev/null 2>&1 || true
	@echo "Container $(ACTUATOR_CONTAINER_NAME) parado e removido (se existia)."
	@echo "Tentando parar e remover o container $(BROKER_CONTAINER_NAME)..."
	@sudo docker stop $(BROKER_CONTAINER_NAME) >/dev/null 2>&1 || true
	@sudo docker rm $(BROKER_CONTAINER_NAME) >/dev/null 2>&1 || true
	@echo "Container $(BROKER_CONTAINER_NAME) parado e removido (se existia)."
	@echo "Tentando parar e remover o container $(MONITOR_CONTAINER_NAME)..."
	@sudo docker stop $(MONITOR_CONTAINER_NAME) >/dev/null 2>&1 || true
	@sudo docker rm $(MONITOR_CONTAINER_NAME) >/dev/null 2>&1 || true
	@echo "Container $(MONITOR_CONTAINER_NAME) parado e removido (se existia)."
	@echo "Tentando parar e remover o container $(AI_ENGINE_CONTAINER_NAME)..."
	@sudo docker stop $(AI_ENGINE_CONTAINER_NAME) >/dev/null 2>&1 || true
	@sudo docker rm $(AI_ENGINE_CONTAINER_NAME) >/dev/null 2>&1 || true
	@echo "Container $(AI_ENGINE_CONTAINER_NAME) parado e removido (se existia)."
	@echo "Processo de parada de containers concluído."

run-all-containers:
	@echo "Iniciando todos os containers necessários..."
	@make start-broker-container
	@make start-actuator-container
	@make start-monitor-container
	@make start-ai-engine-container
	@echo "Todos os containers iniciados com sucesso."

# Ajuda
help:
	@echo "Available targets:"
	@echo "  all                      : Alias para 'setup-and-start'."
	@echo "  setup-and-start          : Configura a infraestrutura, sobe os containers (broker, actuator, monitor, ai-engine) e inicia o simulador."
	@echo "  start                    : Inicia APENAS o simulador Go (assume que a infraestrutura e as dependências já estão configuradas)."
	@echo "  ---"
	@echo "  Individual setup steps (geralmente chamados por 'setup-and-start'):"
	@echo "    setup-kubernetes-infra : Executa scripts/main.sh para configurar a infraestrutura Kubernetes."
	@echo "  ---"
	@echo "  help                     : Mostra esta mensagem de ajuda."