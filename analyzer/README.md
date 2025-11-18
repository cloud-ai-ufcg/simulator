# Migration Simulator Analyzer

This module analyzes migration simulation data, processes metrics, and generates visualizations and statistical summaries for cluster resource utilization and workload migration patterns.

## Features

- **Resource Analysis**: CPU and memory allocation/request analysis
- **Cluster Metrics**: Load analysis for public and private clusters
- **Migration Tracking**: Visualizes workload migration patterns
- **Pricing Analysis**: Cost comparison between clusters
- **Statistical Summaries**: Comprehensive metrics summaries
- **Timestamped Organization**: All outputs organized by simulation run timestamp

## Directory Structure

```
analyzer/
├── main.py                         # Main entry point (orchestrator)
├── data_loader.py                  # Load JSON and log data
├── data_models.py                  # Data structures (pure models)
├── data_processor.py               # Process metrics data (business logic)
├── plot_data_builder.py            # Prepare data for visualization
├── plotter.py                      # Generate visualizations (pure plotting)
├── metrics_summarizer.py           # Generate statistical summaries
├── pricing_data.py                 # Pricing data definitions
├── pricing_utils.py                # Pricing calculations
├── utils.py                        # Utility functions
├── requirements.txt                # Python dependencies
├── Makefile                        # Build and run automation
├── REFACTORING.md                  # Refactoring documentation
├── ARCHITECTURE.md                 # Architecture diagrams
└── output/                         # Generated outputs (by timestamp)
    └── YYYYMMDD_HHMMSS/           # Each simulation run
        ├── plots/                  # Visualization plots (PNG)
        └── summary/                # Statistical summaries (CSV)
```

## Architecture

The analyzer follows a clean layered architecture with clear separation of concerns:

1. **Load**: Read raw data from files (`data_loader.py`)
2. **Process**: Convert raw data into structured models (`data_processor.py`, `data_models.py`)
3. **Prepare**: Transform models into DataFrames for plotting (`plot_data_builder.py`)
4. **Visualize**: Generate plots from formatted data (`plotter.py`)
5. **Summarize**: Calculate statistics (`metrics_summarizer.py`)

See [ARCHITECTURE.md](ARCHITECTURE.md) for detailed diagrams and [REFACTORING.md](REFACTORING.md) for implementation details.

````

## Installation

### Using Makefile (Recommended)

```bash
make setup
````

This will:

1. Create a Python virtual environment
2. Install all required dependencies

### Manual Installation

```bash
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
```

## Usage

### Using Makefile (Recommended)

```bash
# Generate plots from a simulation run directory
make generate-plots RUN_DIR=../simulator/data/output/20251101_120000

# Or use the run target (equivalent)
make run RUN_DIR=../simulator/data/output/20251101_120000
```

The `RUN_DIR` should point to a simulation run directory containing:

- `metrics.json` (required)
- `logs/actuator.log` (optional, for migration tracking)

### Direct Python Execution

```bash
# Activate virtual environment
source venv/bin/activate

# Run analyzer
python main.py ../simulator/data/output/20251101_120000
```

### From Simulator (Automatic)

The analyzer is automatically called at the end of each simulation run. The simulator will:

1. Create a timestamped directory in `simulator/data/output/YYYYMMDD_HHMMSS/`
2. Save metrics.json and logs there
3. Call `make generate-plots` with the run directory
4. Analyzer saves outputs to `analyzer/output/YYYYMMDD_HHMMSS/`

## Input Format

### Run Directory Structure

```
simulator/data/output/20251101_120000/
├── metrics.json              # Required: Complete metrics data
└── logs/                     # Optional: Container logs
    ├── actuator.log         # For migration event tracking
    ├── broker.log
    ├── monitor.log
    ├── ai-engine.log
    └── kubectl.log
```

### metrics.json

Contains timestamped metrics data from the Monitor component:

- Cluster capacity (CPU, memory)
- Cluster load metrics
- Workload information
- Pod status (running, pending)
- Resource requests and allocations

### logs/actuator.log

Contains migration event logs for tracking workload movements between clusters.

## Output Files

### Plots (PNG files in `output/<timestamp>/plots/`)

1. **allocated_cpu.png** - CPU allocation across clusters
2. **requested_cpu.png** - CPU requests across clusters
3. **allocated_memory.png** - Memory allocation across clusters
4. **requested_memory.png** - Memory requests across clusters
5. **cpu_load.png** - CPU load percentages over time
6. **memory_load.png** - Memory load percentages over time
7. **total_percent_pending.png** - Pending pods percentage
8. **pricing\_\*.png** - Various pricing comparison plots

### Summary (JSON files in `output/<timestamp>/summary/`)

- Statistical summaries of all metrics
- Min, max, mean, and median values
- Migration event summaries

## Makefile Targets

```bash
make help           # Show available targets
make setup          # Install dependencies
make run            # Run analyzer (requires RUN_DIR)
make generate-plots # Generate plots (requires RUN_DIR)
make clean          # Remove output files
make clean-all      # Remove output files and venv
```

## Requirements

- Python 3.8+
- pandas
- matplotlib
- seaborn
- plotnine

See `requirements.txt` for exact versions.

## Example Workflow

### 1. Run a Simulation

```bash
cd ../simulator
make setup-and-start
```

This creates a run directory: `simulator/data/output/20251101_120000/`

### 2. View Results

The analyzer runs automatically, but you can also run it manually:

```bash
cd ../analyzer
make generate-plots RUN_DIR=../simulator/data/output/20251101_120000
```

### 3. Find Your Outputs

```bash
ls -la output/20251101_120000/plots/
ls -la output/20251101_120000/summary/
```

### 4. Analyze Different Runs

```bash
# List available runs
ls -la ../simulator/data/output/

# Analyze a specific run
make generate-plots RUN_DIR=../simulator/data/output/20251029_150000
```
