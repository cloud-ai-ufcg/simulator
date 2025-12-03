from script.build_script_math import generate
from script.fix_the_duplication import clean_duplicates
from script.orphan_check import check_integrity
from script.plot_gen import generate_plot
from script.plot_pods import generate_pods_plot
from script.show_behavior import show_behavior
from pathlib import Path

# Main execution pattern:
SHOW_IT = True

# Directories
ROOT_PATH = Path(__file__).resolve().parent
OUTPUT_DIR = ROOT_PATH / "data-generated"

INPUT_DIR_OUT = OUTPUT_DIR / "input.json"
PLOT_DIR_OUT = ROOT_PATH / "plot"

# Simulation patterns:
# List composed of (timestamp, percentage)
WEIGHTS_PLANNED = [
    (1, 0.1),
    (80, 1),
    (120, 0.5),
    (130, 0)
]

# Fixed values for the workloads (the MAXIMUM_TIMESTAMP must be equal to the last indicated in WEIGHTS_PLANNED)
MAXIMUM_REPLICAS = 6
MAXIMUM_TIMESTAMP = 130
NUMBER_OF_JOBS = 0
NUMBER_OF_DEPLOYMENTS = 100

# Resources default for each workload
CPU_DEFAULT = "1"  # Core
MEMORY_DEFAULT = "2"  # GiB

# "Factor refresh", this parameter defines the number of input updates (every X seconds it will update the events).
# This parameter is important, there is a relationship between its value and the timestamps defined in weights_planned. If you get the error: "invalid weight list!", it comes from there.
# To fix it, just adjust the list and the final timestamp.
FACTOR = 30

if __name__ == "__main__":
    input_generated = generate(
        FACTOR,
        OUTPUT_DIR,
        WEIGHTS_PLANNED,
        MAXIMUM_REPLICAS,
        MAXIMUM_TIMESTAMP,
        NUMBER_OF_JOBS,
        NUMBER_OF_DEPLOYMENTS,
        CPU_DEFAULT,
        MEMORY_DEFAULT,
    )

    clean_duplicates(input_generated, INPUT_DIR_OUT)
    check_integrity(INPUT_DIR_OUT)
    generate_plot(INPUT_DIR_OUT, PLOT_DIR_OUT)
    generate_pods_plot(INPUT_DIR_OUT, PLOT_DIR_OUT)

    if SHOW_IT:
        show_behavior(PLOT_DIR_OUT)
