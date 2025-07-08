import subprocess
import os

ORIGINAL_PATH = "./charts/cluster-autoscaler/templates/configmap.yaml"

cpu_env = os.environ['MEMBER2_CPU']
mem_env = os.environ['MEMBER2_MEM']

CPU_VALUE = f'"{cpu_env}"'
MEMORY_VALUE = f'"{mem_env}"'

brute_content = subprocess.run(["cat", "-A", ORIGINAL_PATH], capture_output=True, text=True)
content = (brute_content.stdout).split("$")

for i in range(len(content)):
    line = content[i]

    if "capacity:" in line or "allocatable" in line:
        cpu_changed = False 
        mem_changed = False 

        for j in range(i, len(content)):
            element = content[j]

            if cpu_changed and mem_changed:
                break

            if "cpu:" in element:
                content[j] = f"\n          cpu: {CPU_VALUE}"
                cpu_changed = True
            elif "memory:" in element:
                content[j] = f"\n          memory: {MEMORY_VALUE}"
                mem_changed = True

with open(ORIGINAL_PATH, "w") as f:
    f.write("".join(content))