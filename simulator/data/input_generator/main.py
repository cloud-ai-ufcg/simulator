from script.build_script_math import generate
from script.fix_the_duplication import clean_duplicates
from script.orphan_check import check_integrity
from script.plot_gen import generate_plot
from script.plot_pods import generate_pods_plot
from script.show_behavior import show_behavior
from pathlib import Path

# Padrão de execução main:
SHOW_IT = True

# Padrões de diretório:
ROOT_PATH = Path(__file__).resolve().parent
OUTPUT_DIR = ROOT_PATH / "output"

INPUT_DIR_OUT = OUTPUT_DIR / "input.json"
PLOT_DIR_OUT = ROOT_PATH / "plot"

# Padrões de simulação:
# Lista composta de (timestamp, porcentagem)
WEIGHTS_PLANNED = [
    (1, 0.1),
    (180, 1),
    (300, 1),
    (420, 0.5),
    (450, 0.5),
    (510, 0.1),
    (540, 0.1),
    (600, 0.7),
    (720, 0.7),
]

# Valores fixados para os workloads (o MAXIMUM_TIMESTAMP deve ser igual a o último indicado no WEIGHTS_PLANNED)
MAXIMUM_REPLICAS = 6
MAXIMUM_TIMESTAMP = 720
NUMBER_OF_JOBS = 0
NUMBER_OF_DEPLOYMENTS = 30

# Recusos fixos para cada workload
CPU_DEFAULT = "1"  # Core
MEMORY_DEFAULT = "2"  # GiB

# "Factor refresh", esse parâmetro define a quantidade de atualizações do input (a cada X segundos ele atualizará os eventos).
# Esse parâmetro é importante, há uma relação entre o valor dele e os timestamps definidos no weights_planned. Se você tiver o erro: "invalid weight list!", vem daí.
# Para corrigir, basta ajustar a lista e o timestamp final.
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
