from script.collect_occurrence import label_to_input
from script.plot_gen import plot_gen
from pathlib import Path

# Directory patterns:
ROOT_PATH = Path(__file__).resolve().parent
OUTPUT_DIR = ROOT_PATH / "output"

# Expects the metrics and the input file to be modified...
INPUT_DIR = ROOT_PATH / "input" / "input.json"
METRICS_DIR = ROOT_PATH / "input" / "metrics.json"
PLOT_DIR_OUT = ROOT_PATH / "plot" 

if __name__ == "__main__":
    label_to_input(METRICS_DIR, INPUT_DIR)
    plot_gen(INPUT_DIR, PLOT_DIR_OUT)