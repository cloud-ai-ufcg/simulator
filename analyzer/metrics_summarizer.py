from unittest import result
import pandas as pd
from plotnine import stat_function
from utils import parse_resource_value


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
    cost_list = []

    for info in list_of_cluster_info:
        private_cost = info[0]["interval_cost"]
        public_cost = info[1]["interval_cost"]

        local_total_cost = private_cost + public_cost
        cost_list.append(local_total_cost)
    
    return cost_list


def summarize(raw_data):
    """
    Receives a `raw_data` representing the metrics to summarize it.
    """
    grouped_data = grouping_elements(raw_data)
    data = {
        "cost" : summarize_cost(grouped_data["cluster_info"]),
        "cpu_usage" : [],
        "mem_usage" : [],
        "pods_pending" : [],
        "time_with_pending" : [],
        "wokloads_with_pending_pods" : [],
        "number_of_migrations" : []
    }

    stat_functions = ["mean", "min", "max", "std"]
    data_frame = pd.DataFrame(data).T
    out = data_frame.agg(stat_functions)
    
    result = out.T 
