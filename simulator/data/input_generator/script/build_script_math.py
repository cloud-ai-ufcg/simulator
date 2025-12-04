import random as r
import json

weights_planned = [(1, 0.1), (180, 1), (300, 1), (420, 0.5), (450, 0.5), (510, 0.1), (540, 0.1), (600, 0.7), (720, 0.7)]

output_dir = ""

maximum_replicas = 6
maximum_timestamp = 720
number_of_jobs = 0
number_of_deployments = 100

randomic_caos = False

cpu_default = "1"
memory_default = "2"

WORKLOAD_PATTERN = {
    "id": "",
    "kind": "",
    "action": "",
    "replicas": "",
    "cpu": cpu_default,
    "memory": memory_default,
    "job_duration": "",
    "label": "",
    "timestamp": 0,
}

out = {"config": {"kubeconfig": "karmada.config", "namespace": "default"}, "data": []}
non_constant_workloads = []

def load_workload_pattern():
    global WORKLOAD_PATTERN

    WORKLOAD_PATTERN = {
    "id": "",
    "kind": "",
    "action": "",
    "replicas": "",
    "cpu": cpu_default,
    "memory": memory_default,
    "job_duration": "",
    "label": "",
    "timestamp": 0,
    }

def generate_template(
    work_id, action, replicas, job_duration, kind, timestamp, label=""
):
    current_obj = WORKLOAD_PATTERN.copy()

    current_obj["id"] = work_id
    current_obj["action"] = action
    current_obj["replicas"] = replicas
    current_obj["job_duration"] = job_duration
    current_obj["label"] = label
    current_obj["kind"] = kind
    current_obj["timestamp"] = timestamp

    return current_obj


def generate_workloads_over_time() -> list:
    out = []

    for deploy_id in range(number_of_deployments):
        deploy = generate_template(
            f"{deploy_id}", "void", str(maximum_replicas), "", "deployment", 0
        )
        out.append(deploy)

    for job_id in range(number_of_jobs):
        job_duration = str(r.randint(120, 180))
        job = generate_template(
            f"{job_id}-1", "void", str(maximum_replicas), job_duration, "deployment", 0
        )

        out.append(job)

    return out


def build_event(target_list_workload, target_item, action, timestamp):
    global out

    target_item["action"] = action
    target_item["timestamp"] = timestamp
    target_list_workload.append(target_item)

    out["data"].append(target_item.copy())


def generate_events(weight: list, factor: int):
    if len(weight) < 2:
        print("invalid weight list!")
        return

    if maximum_timestamp // factor >= len(weight):
        print("Incompatible weight size!")
        return

    if factor <= 0:
        print("Incompatible factor!")
        return

    global out
    base_workloads = generate_workloads_over_time()
    total_workloads = len(base_workloads)
    running_workloads = []
    r.shuffle(base_workloads)

    initial_weight = weight.pop(0)
    target_total = int(total_workloads * initial_weight)
    for _ in range(target_total):
        target_item = base_workloads.pop(0)
        build_event(running_workloads, target_item, "create", 1)

    local_time = factor
    for current_weight in weight:
        target_total = int(total_workloads * current_weight)
        current_running = len(running_workloads)

        if current_running < target_total:
            for _ in range(target_total - current_running):
                if base_workloads:
                    target_item = base_workloads.pop(0)
                    build_event(running_workloads, target_item, "create", local_time)

        elif current_running > target_total:
            for _ in range(current_running - target_total):
                if running_workloads:
                    target_item = running_workloads.pop(0)
                    build_event(base_workloads, target_item, "delete", local_time)

        local_time += factor

    if out["data"][-1]["timestamp"] < maximum_timestamp:
        final_time = maximum_timestamp + 10
        finalizer_workload = generate_template("finalizer", "create", "0", "", "deployment", final_time)

        build_event(running_workloads, finalizer_workload, "create", final_time)


def save_data():
    with open(output_dir, "w", encoding="utf-8") as f:
        json.dump(out, f, indent=2, ensure_ascii=False)


def fill_events_using_math(weights: list[tuple], disposing_factor: int):
    """
    It waits a list containing tuples that represents (time_moment, weight) and returns
    a list containing the weights distribuited over the time. It also uses the `disposing_form`
    to decide how many points of weight allocation there will be between two points.
    The weights must initiate from the zero moment.
    """

    if len(weights) < 2:
        raise "weight length is incompatible"
    if disposing_factor == 0:
        raise "disposing factor is incompatible"

    weights_over_time = [weights[0][1]]  # store the weights over the time
    pointer = 0

    for idx in range(0, len(weights) - 1):
        current_pair, next_pair = weights[idx], weights[idx + 1]

        number_of_points = abs(current_pair[0] - next_pair[0]) / disposing_factor
        weight_per_point = (next_pair[1] - current_pair[1]) / number_of_points

        for j in range(int(number_of_points)):
            previous_weight = weights_over_time[pointer]
            next_weight = previous_weight + weight_per_point

            weights_over_time.append(round(next_weight, 3))
            pointer += 1

    return weights_over_time


def fill_events_using_math1(weights: list[tuple], disposing_factor: int):
    """
    Distributes weights over time based on (time_moment, weight) tuples.
    Returns a list of weights allocated at each time step, including the final weight.
    """
    if len(weights) < 2:
        raise ValueError("weight length is incompatible")
    if disposing_factor == 0:
        raise ValueError("disposing factor is incompatible")
    weights_over_time = [weights[0][1]]  # Start with the initial weight

    for idx in range(len(weights) - 1):
        current_pair, next_pair = weights[idx], weights[idx + 1]
        interval = abs(current_pair[0] - next_pair[0])
        number_of_points = int(round(interval / disposing_factor))
        if number_of_points == 0:
            continue
        weight_per_point = (next_pair[1] - current_pair[1]) / number_of_points
        for j in range(1, number_of_points + 1):
            next_weight = current_pair[1] + weight_per_point * j
            weights_over_time.append(round(next_weight, 3))

    return weights_over_time

def generate(factor, output_directory, weights, max_replicas, max_timestamp, num_of_jobs, num_of_deployments, cpu_default_st, memory_default_st):
    global output_dir, weights_planned, maximum_replicas, maximum_timestamp, number_of_jobs, number_of_deployments, cpu_default, memory_default
    
    output_dir = output_directory
    weights_planned = weights
    maximum_replicas = max_replicas
    maximum_timestamp = max_timestamp
    number_of_deployments = num_of_deployments
    number_of_jobs = num_of_jobs
    cpu_default = cpu_default_st
    memory_default = memory_default_st

    filled_arr = fill_events_using_math1(weights, factor)
    load_workload_pattern()
    generate_events(filled_arr, factor)

    return out


if __name__ == "__main__":
    factor = 30  # update rate in seconds
    filled_arr = fill_events_using_math1(
        weights_planned,
        factor,
    )

    generate_events(
        filled_arr,
        factor,
    )

    save_data()
