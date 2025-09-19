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

    -------
    Returns: it returns a dictionary with two keys: "pending_pods" and "percent_workloads". 
    Each key contains a dictionary with the statistical summary (mean, min, max, std, median) of the respective metric.
    """
    pending_pods_list = []
    percent_workloads_list = []
    
    for workloads in list_of_workloads:
        pending_sum = 0
        workload_pending = 0
        total_workloads = len(workloads)

        for workload in workloads:
            pending_sum += workload["pods_pending"]
            
            if workload["pods_pending"] > 0:
                workload_pending += 1

        final_percent = (workload_pending / total_workloads) if total_workloads > 0 else 0
        pending_pods_list.append(pending_sum)
        percent_workloads_list.append(final_percent)

    pending_pods_series = pd.Series(pending_pods_list)
    percent_pods_list_series = pd.Series(percent_workloads_list)

    return {"pending_pods": pending_pods_series.agg(STAT_FUNCTION).to_dict(), "percent_workloads": percent_pods_list_series.agg(STAT_FUNCTION).to_dict()}

def summarize_time_with_pending(list_of_workloads: list) -> list:
    """
    Calculate the number of periods (timestamps) with pending pods in any workload.
    """
    list_of_time_pending = []

    for workloads in list_of_workloads:
        idx = 0
        has_pending = False
        
        while idx < len(workloads) and not has_pending:
            if workloads[idx]["pods_pending"] > 0:
                list_of_time_pending.append(1)
                has_pending = True
            
            idx += 1
        
        if not has_pending:
            list_of_time_pending.append(0)

    local_serie = pd.Series(list_of_time_pending)
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
    pending_data = summarize_pending_pods(grouped_data["workloads"])

    data = {
        "cost": summarize_cost(grouped_data["cluster_info"]),
        "cpu_usage": summarize_resources(grouped_data["cluster_info"], "cpu"),
        "mem_usage": summarize_resources(grouped_data["cluster_info"], "memory"),
        "pending_pods": pending_data["pending_pods"],
        "time_with_pending": summarize_time_with_pending(grouped_data["workloads"]),
        "wokloads_with_pending_pods": pending_data["percent_workloads"],
        "number_of_migrations": pending_data["pending_pods"],  # TODO
    }

    summary_result = pd.DataFrame.from_dict(data, orient="index")
    save_summary(summary_result, summary_dir)
