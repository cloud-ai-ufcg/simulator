SHELL := /bin/bash
export PATH := $(PATH):/usr/local/go/bin

ACTUATOR_MODE ?= auto

.PHONY: all setup-and-start setup-and-start-human start setup-kubernetes-infra stop-all-containers restart-all-containers help start-auto-mode start-human-loop-mode run-auto-mode run-all-containers run-all-containers-human setup-baseline run-baseline teardown-baseline setup-and-start-baseline clean-mongo-db

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
	@echo "Starting all containers in auto mode..."
	@bash initializer/setup-environment.sh --components-only
	@echo "All containers started successfully."

# Run containers in human-in-the-loop mode (UI review required)
run-all-containers:
	@echo "Starting all containers in HUMAN-IN-THE-LOOP mode..."
	@ACTUATOR_MODE=human-in-the-loop bash initializer/setup-environment.sh --components-only
	@echo "All containers started successfully in HUMAN-IN-THE-LOOP mode."
	@echo "🎯 Operator UI available at: http://localhost:5173"


# Starts only the Go simulator (assumes infrastructure is already set up)
start: clean-mongo-db
	@(bash initializer/check_infra_status.sh && cd simulator/cmd && go run main.go)

fast-setup:
	@cd scripts && ./fast_deploy.sh

# -----------------------------------------------------------------------------
# Karmada-native baseline (Approach B) — no AI, placement decided purely by
# karmada-scheduler. See scripts/baseline/README.md for the design.
# -----------------------------------------------------------------------------

# Reconfigures a RUNNING environment (after 'make setup') for baseline runs
setup-baseline:
	@bash scripts/baseline/setup_baseline.sh

# Runs one baseline simulation (same input.json and metrics pipeline as AI runs)
run-baseline: clean-mongo-db
	@bash initializer/check_infra_status.sh
	@bash scripts/baseline/run_baseline.sh

# Restores the AI-driven configuration
teardown-baseline:
	@bash scripts/baseline/teardown_baseline.sh

# Full baseline cycle: infra + setup + run + workload cleanup + teardown.
# Teardown always runs (even if the run fails) so the environment is never
#  left in baseline mode by accident;
setup-and-start-baseline: stop-kubernetes-infra stop-all-containers setup-kubernetes-infra run-all-containers-auto
	@bash scripts/baseline/setup_baseline.sh
	@status=0; \
	$(MAKE) run-baseline || status=$$?; \
	bash scripts/clean_workloads.sh || status=$$?; \
	bash scripts/baseline/teardown_baseline.sh || status=$$?; \
	if [ $$status -eq 0 ]; then \
		echo "✅ setup-and-start-baseline finished. Run data: simulator/data/output/$$(cat simulator/data/output/.last_baseline_run)"; \
	fi; \
	exit $$status


# Cleans all documents from all collections in the mongo container
clean-mongo-db:
	@echo "Cleaning all documents from all collections in mongo container..."
	@js='dbs=db.getMongo().getDBNames().filter(function(x){return ["admin","local","config"].indexOf(x)<0});dbs.forEach(function(dbName){db=db.getSiblingDB(dbName);db.getCollectionNames().forEach(function(coll){db[coll].deleteMany({});});});'; \
	attempt=0; max_attempts=60; \
	until container_id=$$(sudo docker ps -q -f name=mongo) && [ -n "$$container_id" ] && sudo docker exec "$$container_id" mongosh --quiet --eval "$$js" >/dev/null 2>&1; do \
		attempt=$$((attempt + 1)); \
		if [ "$$attempt" -ge "$$max_attempts" ]; then \
			echo "ERROR: mongo did not become ready to clean after $$max_attempts attempts (~$$max_attempts s). Aborting."; \
			exit 1; \
		fi; \
		sleep 1; \
	done; \
	echo "All documents removed from all user collections via mongosh in container."

clean-infra:
	@echo "Cleaning infrastructure..."
	@bash scripts/clean_infra.sh
	@echo "Infrastructure cleaned."

# Cleans all workloads from Karmada and member clusters (preserves nodes)
clean-workloads:
	@echo "Cleaning all workloads from Karmada and member clusters (preserving nodes)..."
	@if [ ! -f ~/.kube/karmada.config ] || [ ! -f ~/.kube/members.config ]; then \
		echo "⚠️  Karmada/members config files not found. Is the infrastructure running?"; \
		exit 1; \
	fi
	@bash scripts/clean_workloads.sh
	@echo "✅ All workloads cleaned successfully (nodes preserved)."

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
	@sudo docker compose -f simulator-infra.yaml stop broker monitor ai-engine recommendations-manager mongo
	@sudo docker compose -f simulator-infra.yaml rm -f broker monitor ai-engine recommendations-manager mongo
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
	@echo "  Karmada-native baseline (no AI):"
	@echo "    setup-baseline         : Reconfigures a running environment for baseline runs."
	@echo "    run-baseline           : Runs one baseline simulation (AI disabled)."
	@echo "    teardown-baseline      : Restores the AI-driven configuration."
	@echo "    setup-and-start-baseline : Full cycle: infra + setup + run + plots + cleanup + teardown."
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
	@echo "    clean-infra            : Cleans infrastructure (workloads + KWOK nodes) using clean_infra.sh."
	@echo "    clean-workloads        : Removes only workloads, preserves KWOK nodes."
	@echo "  ---"
	@echo "  Database:"
	@echo "    clean-mongo-db         : Removes all documents from all user collections in mongo."
	@echo "  ---"
	@echo "  help                     : Shows this help message."