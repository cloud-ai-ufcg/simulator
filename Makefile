SHELL := /bin/bash
export PATH := $(PATH):/usr/local/go/bin

ACTUATOR_MODE ?= auto

.PHONY: all setup-and-start setup-and-start-human start setup-kubernetes-infra stop-all-containers restart-all-containers help start-auto-mode start-human-loop-mode run-auto-mode run-all-containers run-all-containers-human

# Default target: sets up infrastructure and runs the simulator
all: setup-and-start

# Verifies if the environment is ready for start
verify-start:
	@scripts/verify_env.sh

# Sets up infrastructure and runs in human-in-the-loop mode
setup-and-start: setup start

# Sets up the complete infrastructure
setup: stop-kubernetes-infra stop-all-containers setup-kubernetes-infra run-all-containers

# Sets up the complete infrastructure and runs the simulator without human-in-the-loop (auto mode)
setup-and-start-auto: stop-kubernetes-infra stop-all-containers setup-kubernetes-infra run-all-containers-auto clean-mongo-db start

# Sets up Kubernetes infrastructure
setup-kubernetes-infra: stop-kubernetes-infra
	@echo -e "\\e[35mStarting Kubernetes infrastructure setup (scripts/main.sh)...\\e[0m"
	@( \
		bash initializer/setup-environment.sh --inframode \
	)
	@echo -e "\\e[35mKubernetes infrastructure setup completed.\\e[0m"

# Starts all required containers via docker-compose
run-all-containers-auto:
	@echo "Updating compose.yaml paths with the user's HOME..."
	@echo scripts/replace_paths_in_compose.sh
	@echo "Starting all necessary containers via docker-compose..."
	@bash initializer/setup-environment.sh --components-only
	@echo "All containers started successfully."

# Run containers in human-in-the-loop mode (UI review required)
run-all-containers:
	@echo "Starting all containers in HUMAN-IN-THE-LOOP mode..."
	@echo "Updating compose.yaml paths with the user's HOME..."
	@echo scripts/replace_paths_in_compose.sh
	@echo "Starting all necessary containers via docker compose (ACTUATOR_MODE=human-in-the-loop)..."
	@ACTUATOR_MODE=human-in-the-loop bash initializer/setup-environment.sh --components-only
	@echo "All containers started successfully in HUMAN-IN-THE-LOOP mode."
	@echo "🎯 Actuator UI available at: http://localhost:5173"


# Starts only the Go simulator (assumes infrastructure is already set up)
start: clean-mongo-db
	@(bash initializer/check_infra_status.sh && cd simulator/cmd && go run main.go)

fast-setup:
	@cd scripts && ./fast_deploy.sh


# Cleans all documents from all collections in the mongo container
clean-mongo-db:
	@echo "Cleaning all documents from all collections in mongo container..."
	@container_id=$$(sudo docker ps -q -f name=mongo); \
	if [ -z "$$container_id" ]; then \
		echo "Mongo container is not running. Nothing to clean."; \
		exit 0; \
	fi; \
	js='dbs=db.getMongo().getDBNames().filter(function(x){return ["admin","local","config"].indexOf(x)<0});dbs.forEach(function(dbName){db=db.getSiblingDB(dbName);db.getCollectionNames().forEach(function(coll){db[coll].deleteMany({});});});'; \
	sudo docker exec $$container_id mongosh --quiet --eval "$$js"; \
	echo "All documents removed from all user collections via mongosh in container."

clean-infra:
	@echo "Cleaning infrastructure..."
	@bash scripts/clean_infra.sh
	@echo "Infrastructure cleaned."

restart-all-containers: clean-mongo-db stop-all-containers run-all-containers
	@echo "All services have been fully restarted."

# Stops KIND cluster containers
stop-kubernetes-infra:
	@echo "Stopping KIND cluster containers and infra-environment..."
	docker rm -f member1-control-plane member2-control-plane karmada-host-control-plane || true
	@sudo docker compose -f simulator-infra.yaml stop infra-environment
	@sudo docker compose -f simulator-infra.yaml rm -f infra-environment
	@echo "KIND containers and infra-environment removed."

# Stops and removes all simulator containers, volumes, and images
stop-all-containers:
	@echo "Stopping and removing all containers and volumes defined in simulator-infra.yaml (except infra-environment)..."
	@sudo docker compose -f simulator-infra.yaml stop broker monitor ai-engine actuator mongo
	@sudo docker compose -f simulator-infra.yaml rm -f broker monitor ai-engine actuator mongo
	@echo "Removing images..."
	@mongo_image_ids=$$(sudo docker images --format '{{.ID}} {{.Repository}}' | grep mongo | awk '{print $$1}'); \
	for img in $$(sudo docker images -q); do \
		if ! echo "$$mongo_image_ids" | grep -q "$$img"; then \
			sudo docker rmi -f $$img 2>/dev/null || true; \
		fi; \
	done
	@echo "Cleanup process completed."

# Help

help:
	@echo "Available targets:"
	@echo "  all                      : Alias for 'setup-and-start'."
	@echo "  verify-start             : Verifies if the environment is ready for 'start'."
	@echo "  ---"
	@echo "  Setup & Start:"
	@echo "    setup                  : Sets up complete infrastructure (stops/starts k8s and containers)."
	@echo "    setup-and-start        : Sets up infrastructure and runs simulator in human-in-the-loop mode."
	@echo "    setup-and-start-auto   : Sets up infrastructure and runs simulator in auto mode (no UI)."
	@echo "    fast-setup             : Fast deployment using fast_deploy.sh script."
	@echo "    start                  : Starts ONLY the Go simulator (assumes infrastructure and containers are running)."
	@echo "  ---"
	@echo "  Container Management:"
	@echo "    run-all-containers     : Starts all containers in human-in-the-loop mode (with UI)."
	@echo "    run-all-containers-auto: Starts all containers in auto mode (no UI)."
	@echo "    restart-all-containers : Stops, removes, and recreates all containers."
	@echo "    stop-all-containers    : Stops and removes all simulator containers, volumes and images."
	@echo "  ---"
	@echo "  Infrastructure:"
	@echo "    setup-kubernetes-infra : Sets up Kubernetes infrastructure via scripts/main.sh."
	@echo "    stop-kubernetes-infra  : Stops KIND cluster containers and infra-environment."
	@echo "    clean-infra            : Cleans infrastructure using clean_infra.sh."
	@echo "  ---"
	@echo "  Database:"
	@echo "    clean-mongo-db         : Removes all documents from all user collections in mongo."
	@echo "  ---"
	@echo "  help                     : Shows this help message."