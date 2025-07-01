#!/usr/bin/env python3
"""
JSON Processing Script

This script processes Kubernetes cluster monitoring data and extracts crucial information
per timestamp, generating a cleaned JSON output with cluster load data and total pending percentage.
"""

import json
import sys
from typing import Dict, Any, List


def calculate_total_percent_pending(workloads: List[Dict[str, Any]]) -> float:
    """
    Calculate the total percentage of pending pods across all workloads.
    
    Args:
        workloads: List of workload dictionaries containing pods_total and pods_pending
        
    Returns:
        float: Percentage of pending pods (0-1)
    """
    total_pods = sum(workload.get('pods_total', 0) for workload in workloads)
    total_pending = sum(workload.get('pods_pending', 0) for workload in workloads)
    
    if total_pods == 0:
        return 0.0
    
    return (total_pending / total_pods)


def calculate_pending_per_cluster(workloads: List[Dict[str, Any]]) -> tuple:
    """
    Calculate the percentage of pending pods across all workloads related to each cluster type (public, private).

    Args:
        workloads: List of workload dictionaries containing pods_total and pods_pending
    
    Returns:
        tuple type: three values containing the number of pending pods in the public cluster, the number 
        of pending pods in the private cluster and the number of pods pending.
    """
    pending_private = 0
    pending_public = 0

    for workload in workloads:
        pods_pending = workload.get('pods_pending')

        if workload.get('cluster_label', 0) == 'private':
            pending_private += pods_pending
        else:
            pending_public += pods_pending

    total_pending = pending_private + pending_public

    return (pending_public, pending_private, total_pending)


def extract_cluster_loads(cluster_info: List[Dict[str, Any]]) -> Dict[str, Dict[str, float]]:
    """
    Extract cluster load information from cluster_info array.
    
    Args:
        cluster_info: List of cluster information dictionaries
        
    Returns:
        Dict containing cluster load data organized by cluster label
    """
    cluster_loads = {}
    
    for cluster in cluster_info:
        cluster_label = cluster.get('cluster_label')
        if cluster_label and 'cluster_load' in cluster:
            cluster_loads[cluster_label] = {
                'cpu': cluster['cluster_load'].get('cpu', 0.0),
                'memory': cluster['cluster_load'].get('memory', 0.0)
            }
    
    return cluster_loads


def process_timestamp_data(timestamp_data: Dict[str, Any]) -> Dict[str, Any]:
    """
    Process data for a single timestamp.
    
    Args:
        timestamp_data: Dictionary containing workloads and cluster_info
        
    Returns:
        Dictionary with processed cluster load and total percent pending
    """
    workloads = timestamp_data.get('workloads', [])
    cluster_info = timestamp_data.get('cluster_info', [])
    
    total_percent_pending = calculate_total_percent_pending(workloads)
    number_pending_public, number_pending_private, total_pending = calculate_pending_per_cluster(workloads)
    
    cluster_loads = extract_cluster_loads(cluster_info)
    
    result = {
        'cluster_load_cpu': {},
        'cluster_load_memory': {},
        'number_of_pods_pending': total_pending,
        'number_pending_public': round(number_pending_public, 3),
        'number_pending_private': round(number_pending_private, 3),
        'total_percent_pending': round(total_percent_pending, 3)
    }
    
    for cluster_label, loads in cluster_loads.items():
        result['cluster_load_cpu'][cluster_label] = loads['cpu']
        result['cluster_load_memory'][cluster_label] = loads['memory']
    
    return result


def process_json_file(input_data: Dict[str, Any]) -> Dict[str, Any]:
    """
    Process the entire JSON input file.
    
    Args:
        input_data: Dictionary containing timestamp-based data
        
    Returns:
        Dictionary with processed data for each timestamp
    """
    result = {}
    
    for timestamp, timestamp_data in input_data.items():
        result[timestamp] = process_timestamp_data(timestamp_data)
    
    return result


def main():
    """Main function to handle file processing."""
    if len(sys.argv) != 3:
        print("Usage: python process_json.py <input_json_file> <output_json_file>")
        sys.exit(1)
    
    input_file = sys.argv[1]
    output_file = sys.argv[2]
    
    try:
        with open(input_file, 'r') as f:
            input_data = json.load(f)
        
        processed_data = process_json_file(input_data)
        
        with open(output_file, 'w') as f:
            json.dump(processed_data, f, indent=2)
        
        print(f"Successfully processed '{input_file}' and saved result to '{output_file}'")
        
    except FileNotFoundError:
        print(f"Error: File '{input_file}' not found.")
        sys.exit(1)
    except json.JSONDecodeError as e:
        print(f"Error: Invalid JSON format in '{input_file}': {e}")
        sys.exit(1)
    except Exception as e:
        print(f"Error: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main() 