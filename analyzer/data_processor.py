import pandas as pd
from typing import Dict, Any, List
from utils import parse_resource_value
from pricing_utils import (
    calculate_infrastructure_cost,
    parse_millicores_to_cores,
    parse_mebibytes_to_gb
)

# Functions from process_json.py
def calculate_total_percent_pending(workloads: List[Dict[str, Any]]) -> float:
    """Calculate the total percentage of pending pods across all workloads."""
    total_pods = sum(workload.get('pods_total', 0) for workload in workloads)
    total_pending = sum(workload.get('pods_pending', 0) for workload in workloads)
    return (total_pending / total_pods) if total_pods > 0 else 0.0

def calculate_pending_per_cluster(workloads: List[Dict[str, Any]]) -> tuple:
    """Calculate the number of pending pods for each cluster type."""
    pending_private = sum(w.get('pods_pending', 0) for w in workloads if w.get('cluster_label') == 'private')
    pending_public = sum(w.get('pods_pending', 0) for w in workloads if w.get('cluster_label') != 'private')
    return pending_public, pending_private, pending_public + pending_private

def extract_cluster_loads(cluster_info: List[Dict[str, Any]]) -> Dict[str, Dict[str, float]]:
    """Extract cluster load information from cluster_info array."""
    cluster_loads = {}
    for cluster in cluster_info:
        cluster_label = cluster.get('cluster_label')
        if cluster_label and 'cluster_load' in cluster:
            cluster_loads[cluster_label] = {
                'cpu': cluster['cluster_load'].get('cpu', 0.0),
                'memory': cluster['cluster_load'].get('memory', 0.0),
                'cpu_requested': cluster['cluster_load'].get('cpu_requested', 0.0),
                'memory_requested': cluster['cluster_load'].get('memory_requested', 0.0)
            }
    return cluster_loads

def process_json_data(input_data: Dict[str, Any]) -> Dict[str, Any]:
    """Process the entire JSON input file into a cleaned dictionary."""
    processed_data = {}
    for timestamp, ts_data in input_data.items():
        workloads = ts_data.get('workloads', [])
        cluster_info = ts_data.get('cluster_info', [])
        
        total_percent_pending = calculate_total_percent_pending(workloads)
        pending_public, pending_private, total_pending = calculate_pending_per_cluster(workloads)
        cluster_loads = extract_cluster_loads(cluster_info)
        
        processed_data[timestamp] = {
            'cluster_load_cpu': {lbl: loads['cpu'] for lbl, loads in cluster_loads.items()},
            'cluster_load_memory': {lbl: loads['memory'] for lbl, loads in cluster_loads.items()},
            'number_of_pods_pending': total_pending,
            'number_pending_public': round(pending_public, 3),
            'number_pending_private': round(pending_private, 3),
            'total_percent_pending': round(total_percent_pending, 3)
        }
    return processed_data

# Functions from processing.py
def process_resources(data):
    """Calcula recursos alocados e requisitados para cada cluster."""
    timestamps = sorted([int(ts) for ts in data.keys()])
    mem_allocated = {'public': [], 'private': []}
    mem_requested = {'public': [], 'private': []}
    cpu_allocated = {'public': [], 'private': []}
    cpu_requested = {'public': [], 'private': []}
    pending_pods = {'public': [], 'private': []}
    
    for ts in timestamps:
        ts_str = str(ts)
        for c in data[ts_str]['cluster_info']:
            label = c['cluster_label']
            mem_cap = parse_resource_value(c['cluster_memory_capacity'], 'Mi') / 1024
            cpu_cap = parse_resource_value(c['cluster_cpu_capacity'], 'm') / 1000
            mem_load = c['cluster_load'].get('memory', 0)
            cpu_load = c['cluster_load'].get('cpu', 0)
            mem_allocated[label].append(mem_cap * min(mem_load, 1.0))
            cpu_allocated[label].append(cpu_cap * min(cpu_load, 1.0))
            mem_requested[label].append(mem_cap * c['cluster_load'].get('memory_requested', 0))
            cpu_requested[label].append(cpu_cap * c['cluster_load'].get('cpu_requested', 0))

        pods_sum_for_ts = {'public': 0, 'private': 0}
        for workload in data[ts_str].get('workloads', []):
            label = workload['cluster_label']
            pending_count = workload.get('pods_pending', 0)
            if label in pods_sum_for_ts:
                pods_sum_for_ts[label] += pending_count
        pending_pods['public'].append(pods_sum_for_ts['public'])
        pending_pods['private'].append(pods_sum_for_ts['private'])

    return timestamps, mem_allocated, mem_requested, cpu_allocated, cpu_requested, pending_pods

def process_cluster_info(data, timestamps, limit_load=True):
    """Processes cluster info (limiting load or not)."""
    result = {k: [] for k in [
        'mem_load_public', 'mem_load_private', 'cpu_load_public', 'cpu_load_private',
        'cpu_capacity_public', 'cpu_capacity_private', 'memory_capacity_public', 'memory_capacity_private',
        'number_pending_public', 'number_pending_private'
    ]}

    for ts in timestamps:
        ts_str = str(ts)
        
        pods_sum_for_ts = {'public': 0, 'private': 0}
        
        for workload in data[ts_str].get('workloads', []):
            label = workload.get('cluster_label')
            pending_count = workload.get('pods_pending', 0)
            if label in pods_sum_for_ts:
                pods_sum_for_ts[label] += pending_count
                
        result['number_pending_public'].append(pods_sum_for_ts['public'])
        result['number_pending_private'].append(pods_sum_for_ts['private'])

        for c in data[ts_str]['cluster_info']:
            mem_load = c['cluster_load'].get('memory', 0)
            cpu_load = c['cluster_load'].get('cpu', 0)
            if limit_load:
                mem_load = min(mem_load, 1.0)
                cpu_load = min(cpu_load, 1.0)
            
            mem_cap = parse_resource_value(c['cluster_memory_capacity'], 'Mi') / 1024
            cpu_cap = parse_resource_value(c['cluster_cpu_capacity'], 'm') / 1000
            
            if c['cluster_label'] == 'public':
                result['mem_load_public'].append(mem_load * mem_cap)
                result['cpu_load_public'].append(cpu_load * cpu_cap)
                result['cpu_capacity_public'].append(cpu_cap)
                result['memory_capacity_public'].append(mem_cap)
            
            elif c['cluster_label'] == 'private':
                result['mem_load_private'].append(mem_load * mem_cap)
                result['cpu_load_private'].append(cpu_load * cpu_cap)
                result['cpu_capacity_private'].append(cpu_cap)
                result['memory_capacity_private'].append(mem_cap)

    return (
        result['mem_load_public'], result['mem_load_private'],
        result['cpu_load_public'], result['cpu_load_private'],
        result['cpu_capacity_public'], result['cpu_capacity_private'],
        result['memory_capacity_public'], result['memory_capacity_private'],
        result['number_pending_public'], result['number_pending_private']
    )

def build_dataframe(timestamps, mem_allocated, mem_requested, cpu_allocated, cpu_requested, pending_pods, cluster_info):
    """Builds a pandas DataFrame from the processed data."""
    index = pd.to_datetime(timestamps, unit='s')
    df = pd.DataFrame({
        'timestamp': index,
        'mem_allocated_public': mem_allocated['public'],
        'mem_allocated_private': mem_allocated['private'],
        'mem_requested_public': mem_requested['public'],
        'mem_requested_private': mem_requested['private'],
        'cpu_allocated_public': cpu_allocated['public'],
        'cpu_allocated_private': cpu_allocated['private'],
        'cpu_requested_public': cpu_requested['public'],
        'cpu_requested_private': cpu_requested['private'],
        'number_pending_public': pending_pods['public'],
        'number_pending_private': pending_pods['private'],
        'cluster_mem_load_public': cluster_info[0],
        'cluster_mem_load_private': cluster_info[1],
        'cluster_cpu_load_public': cluster_info[2],
        'cluster_cpu_load_private': cluster_info[3],
        'cluster_cpu_capacity_public': cluster_info[4],
        'cluster_cpu_capacity_private': cluster_info[5],
        'cluster_memory_capacity_public': cluster_info[6],
        'cluster_memory_capacity_private': cluster_info[7],
    })
    return df

def melt_df_with_cluster_and_cap(df, value_vars, cluster_vars, cap_vars, var_name, value_name, cluster_value_name, cap_value_name, id_vars=['timestamp']):
    """Melts the DataFrame to plot with cluster/capacity."""
    melted = pd.melt(
        df, id_vars=id_vars, value_vars=value_vars, var_name=var_name, value_name=value_name
    )
    melted['cluster'] = melted[var_name].apply(lambda x: 'Public' if 'public' in x else 'Private')
    cluster_df = pd.melt(
        df, id_vars=id_vars, value_vars=cluster_vars, var_name=var_name, value_name=cluster_value_name
    )
    cluster_df['cluster'] = cluster_df[var_name].apply(lambda x: 'Public' if 'public' in x else 'Private')
    cluster_df['type'] = 'cluster_load'
    cap_df = pd.melt(
        df, id_vars=id_vars, value_vars=cap_vars, var_name=var_name, value_name=cap_value_name
    )
    cap_df['cluster'] = cap_df[var_name].apply(lambda x: 'Public' if 'public' in x else 'Private')
    cap_df['type'] = 'capacity'
    return melted, cluster_df, cap_df

def process_pricing_data(data):
    """
    Process pricing data for each cluster over time.
    Calculates infrastructure costs using the same logic as the AI Engine.
    """
    timestamps = sorted([int(ts) for ts in data.keys()])
    pricing_data = {
        'public': [],
        'private': [],
        'public_hourly': [],
        'private_hourly': [],
        'total_cost': []
    }
    
    # Get interval duration (assume 30s if not specified)
    first_ts = str(timestamps[0]) if timestamps else None
    interval_duration = None
    if first_ts and 'interval_duration' in data.get(first_ts, {}):
        interval_str = data[first_ts].get('interval_duration', '30s')
        try:
            interval_duration = int(str(interval_str).rstrip('s'))
        except Exception:
            interval_duration = 30
    else:
        interval_duration = 30
    
    for ts in timestamps:
        ts_str = str(ts)
        cluster_info = data[ts_str].get('cluster_info', [])
        
        # Initialize costs to 0 for this timestamp
        costs_for_ts = {'public': 0.0, 'private': 0.0}
        hourly_costs_for_ts = {'public': 0.0, 'private': 0.0}
        
        for cluster in cluster_info:
            cluster_label = cluster.get('cluster_label')
            if cluster_label not in ['public', 'private']:
                continue
            
            # Get node information
            node_info = cluster.get('node_info', {})
            node_cpu = node_info.get('cpu', 0)
            node_memory = node_info.get('memory', 0)  # Assume GB
            node_quantity = int(node_info.get('quantity', 1) or 1)
            
            # If node_info is not available, try to estimate from cluster capacity
            if node_cpu == 0 or node_memory == 0:
                # Try to extract from cluster capacity
                cpu_cap_str = cluster.get('cluster_cpu_capacity', '0m')
                mem_cap_str = cluster.get('cluster_memory_capacity', '0Mi')
                
                # Parse capacity
                total_cpu = parse_millicores_to_cores(cpu_cap_str)
                total_memory = parse_mebibytes_to_gb(mem_cap_str)
                
                # If we have capacity but no node info, estimate node size
                # Assume homogeneous nodes: divide total capacity by node quantity
                if node_quantity > 0 and total_cpu > 0 and total_memory > 0:
                    # Estimate per-node CPU and memory
                    node_cpu = int(total_cpu / node_quantity)
                    node_memory = int(total_memory / node_quantity)
                else:
                    # If we still can't estimate, skip this cluster for this timestamp
                    continue
            
            # Calculate infrastructure cost
            cost_info = calculate_infrastructure_cost(
                node_cpu=int(node_cpu),
                node_memory=int(node_memory),
                node_quantity=node_quantity,
                interval_seconds=interval_duration
            )
            
            if cluster_label in costs_for_ts:
                costs_for_ts[cluster_label] = cost_info['cost_per_interval']
                hourly_costs_for_ts[cluster_label] = cost_info['hourly_cost']
        
        pricing_data['public'].append(costs_for_ts['public'])
        pricing_data['private'].append(costs_for_ts['private'])
        pricing_data['public_hourly'].append(hourly_costs_for_ts['public'])
        pricing_data['private_hourly'].append(hourly_costs_for_ts['private'])
        pricing_data['total_cost'].append(costs_for_ts['public'] + costs_for_ts['private'])
    
    return timestamps, pricing_data

def build_pricing_dataframe(timestamps, pricing_data):
    """
    Build a pandas DataFrame for pricing data.
    Includes costs per interval, hourly costs, and cumulative costs.
    """
    index = pd.to_datetime(timestamps, unit='s')
    df = pd.DataFrame({
        'timestamp': index,
        'cost_public': pricing_data['public'],
        'cost_private': pricing_data['private'],
        'cost_total': pricing_data['total_cost'],
        'cost_public_hourly': pricing_data['public_hourly'],
        'cost_private_hourly': pricing_data['private_hourly'],
    })
    
    # Add time_seconds column for plotting
    start_time = df['timestamp'].min()
    df['time_seconds'] = (df['timestamp'] - start_time).dt.total_seconds()
    
    # Calculate cumulative costs
    df['cumulative_cost_public'] = df['cost_public'].cumsum()
    df['cumulative_cost_private'] = df['cost_private'].cumsum()
    df['cumulative_cost_total'] = df['cost_total'].cumsum()
    
    return df
