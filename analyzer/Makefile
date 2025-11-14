.PHONY: help setup clean run generate-plots list-runs kwok real generate-plots-kwok generate-plots-real

# Default target
help:
	@echo "╔══════════════════════════════════════════════════════════════════╗"
	@echo "║          Multi-Cloud Workload Migration Analyzer                ║"
	@echo "╚══════════════════════════════════════════════════════════════════╝"
	@echo ""
	@echo "🎯 Main Commands:"
	@echo ""
	@echo "  make generate-plots {kwok|real} <timestamp>  : Generate plots and analysis"
	@echo "  make setup                                    : Install Python dependencies"
	@echo "  make list-runs                                : List available simulation runs"
	@echo "  make clean                                    : Remove output files"
	@echo ""
	@echo "📦 Examples:"
	@echo "  make generate-plots kwok 20251113_163427      : 🎭 Analyze KWOK mode data"
	@echo "  make generate-plots real 20251113_163427      : 🌐 Analyze Real mode data"
	@echo ""
	@echo "📝 Alternative syntax (still supported):"
	@echo "  make generate-plots TIMESTAMP=20251102_120000"
	@echo "  make generate-plots RUN_DIR=../simulator/data/output/20251102_120000"
	@echo ""
	@echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	@echo "🎭 KWOK Mode (Simulated):"
	@echo "  • Metrics are percentages (0-1) multiplied by capacity"
	@echo "  • Fast simulation for testing and development"
	@echo ""
	@echo "🌐 Real Mode (Real Workloads):"
	@echo "  • Metrics are absolute values (cores/GB) from cAdvisor"
	@echo "  • Real resource consumption tracked"
	@echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	@echo ""
	@echo "📁 The run directory should contain:"
	@echo "  - metrics.json (required)"
	@echo "  - logs/actuator.log (optional, for migration tracking)"

# Setup Python virtual environment and install dependencies
setup:
	@echo "Checking Python environment for analyzer..."
	@if [ -d "../venv" ]; then \
		echo "Using project venv at ../venv"; \
		echo "Installing analyzer dependencies..."; \
		../venv/bin/pip install -r requirements.txt; \
	elif [ -d "venv" ]; then \
		echo "Using local venv at ./venv"; \
		echo "Installing dependencies..."; \
		./venv/bin/pip install -r requirements.txt; \
	else \
		echo "No virtual environment found."; \
		echo "Please run 'make setup' from the project root first, or create a local venv:"; \
		echo "  python3 -m venv venv"; \
		echo "  ./venv/bin/pip install -r requirements.txt"; \
		exit 1; \
	fi
	@echo "Setup complete!"

# Run the analyzer
run:
	@FOUND_MODE=""; \
	for arg in $(MAKECMDGOALS); do \
		if [ "$$arg" = "kwok" ]; then \
			FOUND_MODE="kwok"; \
			break; \
		elif [ "$$arg" = "real" ]; then \
			FOUND_MODE="real"; \
			break; \
		fi; \
	done; \
	if [ -z "$$FOUND_MODE" ]; then \
		echo "❌ Error: Execution mode is required!"; \
		echo ""; \
		echo "Usage:"; \
		echo "  make generate-plots {kwok|real} <timestamp>"; \
		echo ""; \
		echo "Examples:"; \
		echo "  make generate-plots kwok 20251113_163427"; \
		echo "  make generate-plots real 20251113_163427"; \
		echo ""; \
		exit 1; \
	fi; \
	MODE="$$FOUND_MODE"; \
	if [ -n "$(RUN_DIR)" ]; then \
		RUN_PATH="$(RUN_DIR)"; \
	elif [ -n "$(TIMESTAMP)" ]; then \
		RUN_PATH="../simulator/data/output/$(TIMESTAMP)"; \
	elif [ "$(words $(MAKECMDGOALS))" -gt 1 ]; then \
		for arg in $(MAKECMDGOALS); do \
			if [ "$$arg" != "run" ] && [ "$$arg" != "generate-plots" ] && [ "$$arg" != "kwok" ] && [ "$$arg" != "real" ]; then \
				TIMESTAMP_ARG="$$arg"; \
				break; \
			fi; \
		done; \
		if [ -n "$$TIMESTAMP_ARG" ]; then \
			RUN_PATH="../simulator/data/output/$$TIMESTAMP_ARG"; \
		fi; \
	else \
		RUN_PATH=""; \
	fi; \
	if [ -z "$$RUN_PATH" ]; then \
		echo "❌ Error: No timestamp specified."; \
		echo ""; \
		echo "Usage:"; \
		echo "  make generate-plots {kwok|real} <timestamp>"; \
		echo ""; \
		echo "Examples:"; \
		echo "  make generate-plots kwok 20251113_163427"; \
		echo "  make generate-plots real 20251113_163427"; \
		echo ""; \
		if [ -d "../simulator/data/output" ]; then \
			echo "Available simulation runs:"; \
			ls -1dt ../simulator/data/output/*/ 2>/dev/null | head -5 | xargs -I {} basename {} || echo "  No runs found"; \
		fi; \
		exit 1; \
	fi; \
	if [ ! -d "$$RUN_PATH" ]; then \
		echo "Error: Directory $$RUN_PATH not found."; \
		echo ""; \
		if [ -d "../simulator/data/output" ]; then \
			echo "Available simulation runs:"; \
			ls -1dt ../simulator/data/output/*/ 2>/dev/null | head -5 | xargs -I {} basename {}; \
		fi; \
		exit 1; \
	fi; \
	if [ ! -f "$$RUN_PATH/metrics.json" ]; then \
		echo "Error: metrics.json not found in $$RUN_PATH"; \
		echo ""; \
		echo "The directory should contain:"; \
		ls -la "$$RUN_PATH" 2>/dev/null || true; \
		exit 1; \
	fi; \
	if [ "$$MODE" = "kwok" ]; then \
		echo "🎭 Running analyzer in KWOK mode with $$RUN_PATH..."; \
	elif [ "$$MODE" = "real" ]; then \
		echo "🌐 Running analyzer in Real mode with $$RUN_PATH..."; \
	fi; \
	if [ -d "../venv" ]; then \
		../venv/bin/python main.py "$$RUN_PATH" --mode "$$MODE"; \
	elif [ -d "venv" ]; then \
		./venv/bin/python main.py "$$RUN_PATH" --mode "$$MODE"; \
	else \
		echo "Error: No Python virtual environment found"; \
		echo "Please run 'make setup' first"; \
		exit 1; \
	fi

# Alias for generate-plots (same as run)
generate-plots: run

# Dummy targets to avoid make errors
kwok:
	@:
real:
	@:

# Catch-all target to handle timestamp as argument
%:
	@:

# List available simulation runs
list-runs:
	@echo "Available simulation runs:"
	@if [ -d "../simulator/data/output" ]; then \
		ls -1dt ../simulator/data/output/*/ 2>/dev/null | head -10 | while read dir; do \
			timestamp=$$(basename "$$dir"); \
			size=$$(du -sh "$$dir" 2>/dev/null | cut -f1); \
			if [ -f "$$dir/metrics.json" ]; then \
				echo "  ✓ $$timestamp ($$size)"; \
			else \
				echo "  ✗ $$timestamp ($$size) - missing metrics.json"; \
			fi; \
		done || echo "  No runs found"; \
	else \
		echo "  Directory ../simulator/data/output not found"; \
	fi
	@echo ""
	@echo "To analyze a run, use:"
	@echo "  make generate-plots RUN_DIR=../simulator/data/output/<timestamp>"

# Clean output files and Python cache
clean:
	@echo "Cleaning output files and cache..."
	@rm -rf output/*/
	@rm -rf __pycache__
	@rm -rf dataplots/*.json dataplots/*.log
	@echo "Clean complete!"

# Clean everything including virtual environment
clean-all: clean
	@echo "Removing virtual environment..."
	@rm -rf venv
	@echo "Clean all complete!"
