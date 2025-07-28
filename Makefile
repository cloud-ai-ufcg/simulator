SHELL := /bin/bash

.PHONY: all setup-and-start start setup-kubernetes-infra stop-all-containers restart-all-containers help

# Default target: sets up infrastructure and runs the simulator
all: setup-and-start

# Sets up the complete infrastructure and runs the simulator
setup-and-start: setup-kubernetes-infra stop-all-containers run-all-containers start
	@echo -e "\\e[32mFull infrastructure setup and simulator startup process completed.\\e[0m"

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

# Starts only the Go simulator (assumes infrastructure is already set up)
start:
	@(cd simulator/cmd && AI_ENGINE="ON" go run main.go)

start-ai-engine-off:
	@(cd simulator/cmd && AI_ENGINE="OFF" go run main.go)

# Sets up Kubernetes infrastructure
setup-kubernetes-infra:
	@echo -e "\\e[35mStarting Kubernetes infrastructure setup (scripts/main.sh)...\\e[0m"
	@( \
		cd scripts && ./main.sh; \
	)
	@echo -e "\\e[35mKubernetes infrastructure setup completed.\\e[0m"

# Stops and removes all simulator containers, volumes, and images
stop-all-containers:
	@echo "Stopping and removing all containers, volumes, and images defined in compose.yaml..."
	@sudo docker-compose -f compose.yaml down -v --rmi all
	@echo "Cleanup process completed."

run-all-containers:
	@echo "Updating compose.yaml paths with the user's HOME..."
	@echo scripts/replace_paths_in_compose.sh
	@echo "Starting all necessary containers via docker-compose..."
	@docker-compose -f compose.yaml up --build -d
	@echo "All containers started successfully."

restart-all-containers: stop-all-containers run-all-containers
	@echo "All services have been fully restarted."

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
# Help

help:
	@echo "Available targets:"
	@echo "  all                      : Alias for 'setup-and-start'."
	@echo "  setup-and-start          : Sets up infrastructure, starts all containers and runs the simulator."
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
	@echo "  Infrastructure:"
	@echo "    setup-kubernetes-infra : Runs scripts/main.sh to set up Kubernetes infrastructure."
	@echo "  ---"
	@echo "  help                     : Shows this help message."