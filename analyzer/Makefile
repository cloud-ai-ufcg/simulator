.PHONY: help setup run generate-plots list-runs clean clean-all install-deps run-all create-plot generate-plot

# Default target
help:
	@echo "Analyzer Makefile"
	@echo ""
	@echo "Available targets:"
	@echo "  setup           - Install Python dependencies"
	@echo "  run             - Run the analyzer"
	@echo "  generate-plots  - Generate plots from simulation data"
	@echo "  list-runs       - List available simulation runs"
	@echo "  clean           - Remove output files and __pycache__"
	@echo "  clean-all       - Remove output files, __pycache__, and venv"
	@echo ""
	@echo "Usage examples:"
	@echo "  make setup"
	@echo "  make list-runs"
	@echo "  make generate-plots 20251102_120000"
	@echo "  make run 20251102_120000"
	@echo ""
	@echo "Alternative syntax (still supported):"
	@echo "  make generate-plots TIMESTAMP=20251102_120000"
	@echo "  make generate-plots RUN_DIR=../simulator/data/output/20251102_120000"
	@echo ""
	@echo "The run directory should contain:"
	@echo "  - metrics.json (required)"
	@echo "  - logs/actuator.log (optional, for migration tracking)"
	@echo ""
	@echo "Legacy R pipeline (reproduces the IEEE paper scenario, not tied to a run dir):"
	@echo "  install-deps    - Install R package dependencies"
	@echo "  run-all         - create-plot + generate-plot"

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
	@# Check if RUN_DIR is provided (new style)
	@if [ -n "$(RUN_DIR)" ]; then \
		RUN_PATH="$(RUN_DIR)"; \
	elif [ -n "$(TIMESTAMP)" ]; then \
		RUN_PATH="../simulator/data/output/$(TIMESTAMP)"; \
	elif [ "$(words $(MAKECMDGOALS))" -gt 1 ]; then \
		TIMESTAMP_ARG="$(word 2,$(MAKECMDGOALS))"; \
		RUN_PATH="../simulator/data/output/$$TIMESTAMP_ARG"; \
	else \
		RUN_PATH=""; \
	fi; \
	if [ -z "$$RUN_PATH" ]; then \
		echo "Error: No run directory or timestamp specified."; \
		echo ""; \
		echo "Usage:"; \
		echo "  make generate-plots <timestamp>"; \
		echo "  make generate-plots TIMESTAMP=20251102_120000"; \
		echo "  make generate-plots RUN_DIR=../simulator/data/output/20251102_120000"; \
		echo ""; \
		echo "Examples:"; \
		echo "  make generate-plots 20251102_120000"; \
		echo "  make run 20251102_120000"; \
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
	echo "Running analyzer with $$RUN_PATH..."; \
	if [ -d "../venv" ]; then \
		../venv/bin/python main.py "$$RUN_PATH"; \
	elif [ -d "venv" ]; then \
		./venv/bin/python main.py "$$RUN_PATH"; \
	else \
		python3 main.py "$$RUN_PATH"; \
	fi

# Alias for generate-plots (same as run)
generate-plots: run

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
	@echo "Cleaning generated plots/summary/processed_data from every run and cache..."
	@rm -rf ../simulator/data/output/*/plots ../simulator/data/output/*/summary ../simulator/data/output/*/processed_data
	@rm -rf __pycache__
	@echo "Clean complete!"

# Clean everything including virtual environment
clean-all: clean
	@echo "Removing virtual environment..."
	@rm -rf venv
	@echo "Clean all complete!"

# -----------------------------------------------------------------------------
# Legacy R pipeline — reproduces the IEEE paper scenario from
# analyzer_input/processed_data.csv, independent of the Python pipeline above.
# -----------------------------------------------------------------------------

install-deps:
	Rscript -e 'install.packages(c("ggplot2", "dplyr", "readr", "tidyr"), repos="https://cran.r-project.org")'

run-all: create-plot generate-plot

create-plot:
	Rscript create_plot_for_input.R

generate-plot:
	Rscript generate_plot.R
