import json

# workload : cluster
occurrences = {
}

def load_occurreces(metrics_path):
    global occurrences

    metrics = json.load(open(metrics_path, "r"))

    for timestampts in metrics.keys():
        for workload in metrics[timestampts]["workloads"]:
            if workload["workload_id"][8:] not in occurrences.keys():
                occurrences[workload["workload_id"][8:]] = workload["cluster_label"]

def update_labels_input(input_data_path):
    global occurrences

    input_data = json.load(open(input_data_path, "r"))

    for workload in input_data["data"]:
        if workload["id"] in occurrences.keys():
            workload["label"] = occurrences[workload["id"]]
            occurrences.pop(workload["id"])
    

    with open(input_data_path, "w") as f:
        json.dump(input_data, f, indent=4, ensure_ascii=False)

def label_to_input(metrics_path, input_path):
    load_occurreces(metrics_path)
    update_labels_input(input_path)