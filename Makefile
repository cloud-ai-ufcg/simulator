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
setup: stop-kubernetes-infra stop-all-containers setup-kubernetes-infra run-all-containers clean-mongo-db

# Sets up the complete infrastructure and runs the simulator without human-in-the-loop (auto mode)
setup-and-start-auto: stop-kubernetes-infra stop-all-containers setup-kubernetes-infra run-all-containers-auto clean-mongo-db start

# Sets up Kubernetes infrastructure
setup-kubernetes-infra:
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
start:
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

# Para derrubar os containers KIND do cluster
stop-kubernetes-infra:
	@echo "Parando containers KIND do cluster e infra-environment..."
	docker rm -f member1-control-plane member2-control-plane karmada-host-control-plane || true
	@sudo docker compose -f simulator-infra.yaml stop infra-environment
	@sudo docker compose -f simulator-infra.yaml rm -f infra-environment
	@echo "Containers KIND e infra-environment removidos."

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

# ──────────────────────────────────────────────────────────────────────────────
# Important Notes
# - You must export the KUBECONFIG variable with the correct files
#   before running commands that use `kubectl`, such as the Broker.
#   Example:
#
#     export KUBECONFIG=~/.kube/karmada.config
#     # or (to view multiple clusters)
#     export KUBECONFIG=~/.kube/karmada.config:~/.kube/members.config
#
# - Without this, the Broker will not be able to create deployments and jobs correctly.
# ──────────────────────────────────────────────────────────────────────────────
# Generates input data for simulation


# Help

help:
	@echo "Available targets:"
	@echo "  all                      : Alias for 'setup-and-start'."
	@echo "  verify-start             : Verifies if the environment is ready for 'start'."
	@echo "  setup-stopand-start          : Sets up infrastructure, starts all containers and runs the simulator."
	@echo "  start                    : Starts ONLY the Go simulator (assumes infrastructure and containers are already running)."
	@echo "  ---"
	@echo "  Container Management:"
	@echo "    run-all-containers     : Starts all required containers via docker-compose."
	@echo "    restart-all-containers : Stops, removes, and recreates all containers, volumes, and images."
	@echo "    stop-all-containers    : Stops and removes all simulator containers, volumes and images via docker-compose."
	@echo "  ---"
	@echo "  Database:"
	@echo "    clean-mongo-db         : Stops the mongo container and removes its data volume."
	@echo "  ---"
	@echo "  Data Generation:"
	@echo "    generate-input         : Generates input data for simulation using the input_generator."
	@echo "  ---"
	@echo "  Infrastructure:"
	@echo "    setup-kubernetes-infra : Runs scripts/main.sh to set up Kubernetes infrastructure."
	@echo "  ---"
	@echo "  help                     : Shows this help message."