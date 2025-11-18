import pandas as pd
import os
from datetime import datetime
from pricing_utils import calculate_infrastructure_cost, parse_millicores_to_cores, parse_mebibytes_to_gb

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


def summarize_cost(list_of_cluster_info: list, interval_seconds: int = 30) -> list:
    """
    Calculate the cost summary from the list of cluster info. Sum the cost of each type of cluster (private and public).
    Now calculates costs using the same logic as process_pricing_data().
    """
    cost_list = []

    for info in list_of_cluster_info:
        # info is a list of cluster dictionaries
        private_cost = 0.0
        public_cost = 0.0
        
        for cluster in info:
            cluster_label = cluster.get('cluster_label')
            if cluster_label not in ['public', 'private']:
                continue
            
            # Get node information
            node_info = cluster.get('node_info', {})
            node_cpu = node_info.get('cpu', 0)
            node_memory = node_info.get('memory', 0)
            node_quantity = int(node_info.get('quantity', 1) or 1)
            
            # If node_info is not available, try to estimate from cluster capacity
            if node_cpu == 0 or node_memory == 0:
                cpu_cap_str = cluster.get('cluster_cpu_capacity', '0m')
                mem_cap_str = cluster.get('cluster_memory_capacity', '0Mi')
                
                total_cpu = parse_millicores_to_cores(cpu_cap_str)
                total_memory = parse_mebibytes_to_gb(mem_cap_str)
                
                if node_quantity > 0 and total_cpu > 0 and total_memory > 0:
                    node_cpu = int(total_cpu / node_quantity)
                    node_memory = int(total_memory / node_quantity)
                else:
                    continue
            
            # Calculate infrastructure cost
            cost_info = calculate_infrastructure_cost(
                node_cpu=int(node_cpu),
                node_memory=int(node_memory),
                node_quantity=node_quantity,
                interval_seconds=interval_seconds
            )
            
            if cluster_label == 'private':
                private_cost = cost_info['cost_per_interval']
            elif cluster_label == 'public':
                public_cost = cost_info['cost_per_interval']

        local_total_cost = private_cost + public_cost
        cost_list.append(local_total_cost)

    if not cost_list:
        # Return zero stats if no costs calculated
        zero_series = pd.Series([0.0])
        return zero_series.agg(STAT_FUNCTION).to_dict()
    
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


def summarize_migrations(migration_df):
    """
    Calculate migration metrics from migration log data.
    """
    if migration_df is None or migration_df.empty:
        zero_series = pd.Series([0])
        return zero_series.agg(STAT_FUNCTION).to_dict()
    
    migrated_pods_per_execution = []
    
    for _, row in migration_df.iterrows():
        migrated_pods_per_execution.append(row['total_migrated_pods'])
    
    pods_series = pd.Series(migrated_pods_per_execution)
    return pods_series.agg(STAT_FUNCTION).to_dict()

def save_summary(summary_result, summary_dir):
    """
    Save the summary result in a CSV file in the summary_dir.
    """
    localtime = datetime.now().strftime("%Y-%m-%d-%H-%M-%S")
    summary_path = os.path.join(summary_dir, f"summary_metrics_{localtime}.csv")
    pd.DataFrame.to_csv(summary_result, summary_path)


def summarize(raw_data, summary_dir, migration_df=None):
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
        "number_of_migrations": summarize_migrations(migration_df),
    }

    summary_result = pd.DataFrame.from_dict(data, orient="index")
    save_summary(summary_result, summary_dir)
