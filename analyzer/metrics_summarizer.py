import pandas as pd
import os
from datetime import datetime

STAT_FUNCTION = ["mean", "min", "max", "std", "median"]


def grouping_elements(raw_data) -> dict:
    """
    Read the raw_data grouping the information over time.
    """
    grouped_data = {"workloads": [], "cluster_info": []}

    for timestamp in raw_data.keys():
        list_of_workloads = raw_data[timestamp]["workloads"]
        list_of_cluster_info = raw_data[timestamp]["cluster_info"]

        grouped_data["workloads"].append(list_of_workloads)
        grouped_data["cluster_info"].append(list_of_cluster_info)

    return grouped_data


def summarize_cost(list_of_cluster_info: list) -> list:
    """
    Calculate the cost summary from the list of cluster info. Sum the cost of each type of cluster (private and public).
    """
    cost_list = []

    for info in list_of_cluster_info:
        private_cost = info[0]["pricing"]["interval_cost"]
        public_cost = info[1]["pricing"]["interval_cost"]

        local_total_cost = private_cost + public_cost
        cost_list.append(local_total_cost)

    local_serie = pd.Series(cost_list)
    return local_serie.agg(STAT_FUNCTION).to_dict()


def summarize_resources(list_of_cluster_info: list, type_resource: str) -> list:
    """
    Calculate the resource summary from the list of cluster info. It considers the sum of resource usage of each type of cluster (private and public).
    """
    resource_list = []

    for info in list_of_cluster_info:
        private_resource = info[0]["cluster_load"][type_resource]
        public_resource = info[1]["cluster_load"][type_resource]

        total_resource = private_resource + public_resource
        resource_list.append(total_resource)

    local_serie = pd.Series(resource_list)
    return local_serie.agg(STAT_FUNCTION).to_dict()


def summarize_pending_pods(list_of_workloads: list) -> list:
    """
    Calculate the pending pods summary from the list of workloads. It considers the sum of pending pods from all workloads in each timestamp. 
    """
    pending_pods_list = []
    
    for workloads in list_of_workloads:
        pending_sum = 0
        for workload in workloads:
            pending_sum += workload["pods_pending"]
        
        pending_pods_list.append(pending_sum)

    local_serie = pd.Series(pending_pods_list)
    return local_serie.agg(STAT_FUNCTION).to_dict()


def save_summary(summary_result, summary_dir):
    """
    Save the summary result in a CSV file in the summary_dir.
    """
    localtime = datetime.now().strftime("%Y-%m-%d-%H-%M-%S")
    summary_path = os.path.join(summary_dir, f"summary_metrics_{localtime}.csv")
    pd.DataFrame.to_csv(summary_result, summary_path)


def summarize(raw_data, summary_dir):
    """
    Receives a `raw_data` representing the metrics to summarize it.
    """
    grouped_data = grouping_elements(raw_data)
    data = {
        "cost": summarize_cost(grouped_data["cluster_info"]),
        "cpu_usage": summarize_resources(grouped_data["cluster_info"], "cpu"),
        "mem_usage": summarize_resources(grouped_data["cluster_info"], "memory"),
        "pending_pods": summarize_pending_pods(grouped_data["workloads"]),
        "time_with_pending": summarize_pending_pods(grouped_data["workloads"]),  # TODO
        "wokloads_with_pending_pods": summarize_pending_pods(
            grouped_data["workloads"]
        ),  # TODO
        "number_of_migrations": summarize_pending_pods(
            grouped_data["workloads"]
        ),  # TODO
    }

    summary_result = pd.DataFrame.from_dict(data, orient="index")
    print(summary_result)
    # save_summary(summary_result, summary_dir)
