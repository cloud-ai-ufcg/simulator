SHELL := /bin/bash

# Global variables
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

# Default target: sets up infrastructure and runs the simulator
all: setup-and-start

# Sets up the complete infrastructure and runs the simulator
setup-and-start: setup-kubernetes-infra start-broker-container start-actuator-container start-monitor-container start-ai-engine-container start
	@echo -e "\\e[32mFull infrastructure setup and simulator startup process completed.\\e[0m"

# Starts the Broker container if it's not running
start-broker-container:
	@echo "Checking if container $(BROKER_CONTAINER_NAME) is already running..."
	@container_id_check=$$(sudo docker ps -q -f name=$(BROKER_CONTAINER_NAME)); \
	if [ -n "$$container_id_check" ]; then \
		echo "INFO: Container $(BROKER_CONTAINER_NAME) (ID: $$container_id_check) is already running."; \
	else \
		echo "INFO: Container $(BROKER_CONTAINER_NAME) is not running. Proceeding with startup..."; \
		echo "Cleaning up old container (if it exists)..."; \
		sudo docker stop $(BROKER_CONTAINER_NAME) >/dev/null 2>&1 || true; \
		sudo docker rm $(BROKER_CONTAINER_NAME) >/dev/null 2>&1 || true; \
		if ! sudo docker image inspect $(BROKER_IMAGE_NAME) > /dev/null 2>&1; then \
			echo "Building image $(BROKER_IMAGE_NAME) from $(BROKER_DIR)/$(BROKER_DOCKERFILE)..."; \
			if [ ! -f $(BROKER_DIR)/$(BROKER_DOCKERFILE) ]; then \
				echo "ERROR: $(BROKER_DIR)/$(BROKER_DOCKERFILE) not found! Cannot build image $(BROKER_IMAGE_NAME)."; \
				exit 2; \
			fi; \
			sudo docker build -t $(BROKER_IMAGE_NAME) -f $(BROKER_DIR)/$(BROKER_DOCKERFILE) $(BROKER_DIR) || { \
				echo "ERROR: Failed to build image $(BROKER_IMAGE_NAME). Check the build error above."; \
				exit 3; \
			}; \
		fi; \
		echo "Starting container $(BROKER_CONTAINER_NAME) from image $(BROKER_IMAGE_NAME)..."; \
		sudo docker run -d --rm \
			--name $(BROKER_CONTAINER_NAME) \
			--network host \
			-p 8080:80 \
			-v $$HOME/.kube/karmada.config:/root/.kube/karmada.config \
			$(BROKER_IMAGE_NAME); \
		echo "Checking status of container $(BROKER_CONTAINER_NAME)..."; \
		sleep 2; \
		new_container_id=$$(sudo docker ps -q -f name=$(BROKER_CONTAINER_NAME)); \
		if [ -n "$$new_container_id" ]; then \
			echo "SUCCESS: Container $(BROKER_CONTAINER_NAME) (ID: $$new_container_id) is running."; \
		else \
			echo "ERROR: Container $(BROKER_CONTAINER_NAME) did not start correctly."; \
			echo "Check Docker logs with: sudo docker logs $(BROKER_CONTAINER_NAME)"; \
			exit 1; \
		fi; \
		echo "Container check for $(BROKER_CONTAINER_NAME) completed."; \
	fi

# Starts the Actuator container if it's not running
start-actuator-container:
	@echo "Checking if container $(ACTUATOR_CONTAINER_NAME) is already running..."
	@container_id_check=$$(sudo docker ps -q -f name=$(ACTUATOR_CONTAINER_NAME)); \
	if [ -n "$$container_id_check" ]; then \
		echo "INFO: Container $(ACTUATOR_CONTAINER_NAME) (ID: $$container_id_check) is already running."; \
	else \
		echo "INFO: Container $(ACTUATOR_CONTAINER_NAME) is not running. Proceeding with startup..."; \
		echo "Cleaning up old container (if it exists)..."; \
		sudo docker stop $(ACTUATOR_CONTAINER_NAME) >/dev/null 2>&1 || true; \
		sudo docker rm $(ACTUATOR_CONTAINER_NAME) >/dev/null 2>&1 || true; \
		echo "Building image $(ACTUATOR_IMAGE_NAME) from $(ACTUATOR_DIR)/$(ACTUATOR_DOCKERFILE)..."; \
		sudo docker build -t $(ACTUATOR_IMAGE_NAME) -f $(ACTUATOR_DIR)/$(ACTUATOR_DOCKERFILE) $(ACTUATOR_DIR); \
		echo "Starting container $(ACTUATOR_CONTAINER_NAME) from image $(ACTUATOR_IMAGE_NAME)..."; \
		sudo docker run -d --rm \
			--name $(ACTUATOR_CONTAINER_NAME) \
			--network host \
			-v $$HOME/.kube/karmada.config:/root/.kube/config \
			-v $$HOME/.kwok:/home/$$USER/.kwok \
			$(ACTUATOR_IMAGE_NAME); \
		echo "Checking status of container $(ACTUATOR_CONTAINER_NAME)..."; \
		sleep 2; \
		new_container_id=$$(sudo docker ps -q -f name=$(ACTUATOR_CONTAINER_NAME)); \
		if [ -n "$$new_container_id" ]; then \
			echo "SUCCESS: Container $(ACTUATOR_CONTAINER_NAME) (ID: $$new_container_id) is running."; \
		else \
			echo "ERROR: Container $(ACTUATOR_CONTAINER_NAME) did not start correctly."; \
			echo "Check Docker logs with: sudo docker logs $(ACTUATOR_CONTAINER_NAME)"; \
			exit 1; \
		fi; \
		echo "Container check for $(ACTUATOR_CONTAINER_NAME) completed."; \
	fi

# Starts the Monitor container if it's not running
start-monitor-container:
	@echo "Checking if container $(MONITOR_CONTAINER_NAME) is already running..."
	@container_id_check=$$(sudo docker ps -q -f name=$(MONITOR_CONTAINER_NAME)); \
	if [ -n "$$container_id_check" ]; then \
		echo "INFO: Container $(MONITOR_CONTAINER_NAME) (ID: $$container_id_check) is already running."; \
	else \
		echo "INFO: Container $(MONITOR_CONTAINER_NAME) is not running. Proceeding with startup..."; \
		echo "Cleaning up old container (if it exists)..."; \
		sudo docker stop $(MONITOR_CONTAINER_NAME) >/dev/null 2>&1 || true; \
		sudo docker rm $(MONITOR_CONTAINER_NAME) >/dev/null 2>&1 || true; \
		if ! sudo docker image inspect $(MONITOR_IMAGE_NAME) > /dev/null 2>&1; then \
			echo "Building image $(MONITOR_IMAGE_NAME) from $(MONITOR_DIR)..."; \
			sudo docker build -t $(MONITOR_IMAGE_NAME) $(MONITOR_DIR) || { \
				echo "ERROR: Failed to build image $(MONITOR_IMAGE_NAME). Check the build error above."; \
				exit 3; \
			}; \
		fi; \
		echo "Starting container $(MONITOR_CONTAINER_NAME) from image $(MONITOR_IMAGE_NAME)..."; \
		sudo docker run -d --rm \
			--name $(MONITOR_CONTAINER_NAME) \
			--network host \
			$(MONITOR_IMAGE_NAME); \
		echo "Checking status of container $(MONITOR_CONTAINER_NAME)..."; \
		sleep 2; \
		new_container_id=$$(sudo docker ps -q -f name=$(MONITOR_CONTAINER_NAME)); \
		if [ -n "$$new_container_id" ]; then \
			echo "SUCCESS: Container $(MONITOR_CONTAINER_NAME) (ID: $$new_container_id) is running."; \
		else \
			echo "ERROR: Container $(MONITOR_CONTAINER_NAME) did not start correctly."; \
			echo "Check Docker logs with: sudo docker logs $(MONITOR_CONTAINER_NAME)"; \
			exit 1; \
		fi; \
		echo "Container check for $(MONITOR_CONTAINER_NAME) completed."; \
	fi

# Starts the AI-Engine container if it's not running
start-ai-engine-container:
	@echo "Checking if container $(AI_ENGINE_CONTAINER_NAME) is already running..."
	@container_id_check=$$(sudo docker ps -q -f name=$(AI_ENGINE_CONTAINER_NAME)); \
	if [ -n "$$container_id_check" ]; then \
		echo "INFO: Container $(AI_ENGINE_CONTAINER_NAME) (ID: $$container_id_check) is already running."; \
	else \
		echo "INFO: Container $(AI_ENGINE_CONTAINER_NAME) is not running. Proceeding with startup..."; \
		echo "Cleaning up old container (if it exists)..."; \
		sudo docker stop $(AI_ENGINE_CONTAINER_NAME) >/dev/null 2>&1 || true; \
		sudo docker rm $(AI_ENGINE_CONTAINER_NAME) >/dev/null 2>&1 || true; \
		echo "Building image $(AI_ENGINE_IMAGE_NAME) from $(AI_ENGINE_DIR)..."; \
		sudo docker build -t $(AI_ENGINE_IMAGE_NAME) -f $(AI_ENGINE_DIR)/Dockerfile.api $(AI_ENGINE_DIR); \
		echo "Starting container $(AI_ENGINE_CONTAINER_NAME) from image $(AI_ENGINE_IMAGE_NAME)..."; \
		sudo docker run -d --rm \
			--name $(AI_ENGINE_CONTAINER_NAME) \
			--network host \
			-p 8083:8083 \
			$(AI_ENGINE_IMAGE_NAME); \
		echo "Checking status of container $(AI_ENGINE_CONTAINER_NAME)..."; \
		sleep 2; \
		new_container_id=$$(sudo docker ps -q -f name=$(AI_ENGINE_CONTAINER_NAME)); \
		if [ -n "$$new_container_id" ]; then \
			echo "SUCCESS: Container $(AI_ENGINE_CONTAINER_NAME) (ID: $$new_container_id) is running."; \
		else \
			echo "ERROR: Container $(AI_ENGINE_CONTAINER_NAME) did not start correctly."; \
			echo "Check Docker logs with: sudo docker logs $(AI_ENGINE_CONTAINER_NAME)"; \
			exit 1; \
		fi; \
		echo "Container check for $(AI_ENGINE_CONTAINER_NAME) completed."; \
	fi

# Starts only the Go simulator (assumes infrastructure is already set up)
start:
	@echo "Starting the Go Simulator..."
	@( \
		set -e; \
		_EFFECTIVE_HOME="$$HOME"; \
		if grep -qEi "(Microsoft|WSL)" /proc/version &> /dev/null ; then \
			_WIN_USER=$$(cmd.exe /c "echo %USERNAME%" 2>/dev/null | tr -d '\\r'); \
			if [ -z "$$_WIN_USER" ]; then \
				echo "Error: Could not detect Windows user. Make sure WSL is configured correctly."; \
				exit 1; \
			fi; \
			_EFFECTIVE_HOME="/mnt/c/Users/$$_WIN_USER"; \
		fi; \
		HOME="$$_EFFECTIVE_HOME" go run main.go; \
		echo "Go Simulator finished."; \
	)

start-off-engine:
	@echo "Starting the Go Simulator (AI-Engine OFF)..."
	@( \
		set -e; \
		_EFFECTIVE_HOME="$$HOME"; \
		if grep -qEi "(Microsoft|WSL)" /proc/version &> /dev/null ; then \
			_WIN_USER=$$(cmd.exe /c "echo %USERNAME%" 2>/dev/null | tr -d '\\r'); \
			if [ -z "$$_WIN_USER" ]; then \
				echo "Error: Could not detect Windows user. Make sure WSL is configured correctly."; \
				exit 1; \
			fi; \
			_EFFECTIVE_HOME="/mnt/c/Users/$$_WIN_USER"; \
		fi; \
		AI_ENGINE_ROUTE="/stop" HOME="$$_EFFECTIVE_HOME" go run main.go; \
		echo "Go Simulator finished."; \
	)

# Sets up Kubernetes infrastructure
setup-kubernetes-infra:
	@echo -e "\\e[35mStarting Kubernetes infrastructure setup (scripts/main.sh)...\\e[0m"
	@( \
		cd scripts && ./main.sh; \
	)
	@echo -e "\\e[35mKubernetes infrastructure setup completed.\\e[0m"


# Stops and removes Actuator and Broker containers
stop-all-containers:
	@echo "Attempting to stop and remove container $(ACTUATOR_CONTAINER_NAME)..."
	@sudo docker stop $(ACTUATOR_CONTAINER_NAME) >/dev/null 2>&1 || true
	@sudo docker rm $(ACTUATOR_CONTAINER_NAME) >/dev/null 2>&1 || true
	@echo "Container $(ACTUATOR_CONTAINER_NAME) stopped and removed (if it existed)."
	@echo "Attempting to stop and remove container $(BROKER_CONTAINER_NAME)..."
	@sudo docker stop $(BROKER_CONTAINER_NAME) >/dev/null 2>&1 || true
	@sudo docker rm $(BROKER_CONTAINER_NAME) >/dev/null 2>&1 || true
	@echo "Container $(BROKER_CONTAINER_NAME) stopped and removed (if it existed)."
	@echo "Attempting to stop and remove container $(MONITOR_CONTAINER_NAME)..."
	@sudo docker stop $(MONITOR_CONTAINER_NAME) >/dev/null 2>&1 || true
	@sudo docker rm $(MONITOR_CONTAINER_NAME) >/dev/null 2>&1 || true
	@echo "Container $(MONITOR_CONTAINER_NAME) stopped and removed (if it existed)."
	@echo "Attempting to stop and remove container $(AI_ENGINE_CONTAINER_NAME)..."
	@sudo docker stop $(AI_ENGINE_CONTAINER_NAME) >/dev/null 2>&1 || true
	@sudo docker rm $(AI_ENGINE_CONTAINER_NAME) >/dev/null 2>&1 || true
	@echo "Container $(AI_ENGINE_CONTAINER_NAME) stopped and removed (if it existed)."
	@echo "Container stop process completed."

run-all-containers:
	@echo "Starting all necessary containers..."
	@make start-broker-container
	@make start-actuator-container
	@make start-monitor-container
	@make start-ai-engine-container
	@echo "All containers started successfully."

# Help
help:
	@echo "Available targets:"
	@echo "  all                      : Alias for 'setup-and-start'."
	@echo "  setup-and-start          : Sets up infrastructure, starts all containers (broker, actuator, monitor, ai-engine) and runs the simulator."
	@echo "  start                    : Starts ONLY the Go simulator (assumes infrastructure and containers are already running)."
	@echo "  ---"
	@echo "  Container Management:"
	@echo "    run-all-containers     : Starts all required containers."
	@echo "    stop-all-containers    : Stops and removes all simulator containers."
	@echo "    start-broker-container   : Starts the Broker container."
	@echo "    start-actuator-container : Starts the Actuator container."
	@echo "    start-monitor-container  : Starts the Monitor container."
	@echo "    start-ai-engine-container: Starts the AI-Engine container."
	@echo "  ---"
	@echo "  Infrastructure:"
	@echo "    setup-kubernetes-infra : Runs scripts/main.sh to set up Kubernetes infrastructure."
	@echo "  ---"
	@echo "  help                     : Shows this help message."