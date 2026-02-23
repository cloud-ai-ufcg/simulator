"""
Data Processor (Refactored)

This module processes raw JSON data from simulations and converts it into
structured data models. It focuses purely on data transformation without
any visualization concerns.
"""

from typing import Dict, Any, List, Optional
import pandas as pd
from data_models import (
    ClusterMetrics, PricingMetrics, WorkloadMetrics, 
    MigrationEvent, ProcessedSimulationData
)
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
                'memory_requested': cluster['cluster_load'].get('memory_requested', 0.0),
                'network_receive': cluster['cluster_load'].get('network_receive', 0.0),
                'network_transmit': cluster['cluster_load'].get('network_transmit', 0.0),
                'io_read': cluster['cluster_load'].get('io_read', 0.0),
                'io_write': cluster['cluster_load'].get('io_write', 0.0)
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
            'cluster_load_network_receive': {lbl: loads.get('network_receive', 0.0) for lbl, loads in cluster_loads.items()},
            'cluster_load_network_transmit': {lbl: loads.get('network_transmit', 0.0) for lbl, loads in cluster_loads.items()},
            'cluster_load_io_read': {lbl: loads.get('io_read', 0.0) for lbl, loads in cluster_loads.items()},
            'cluster_load_io_write': {lbl: loads.get('io_write', 0.0) for lbl, loads in cluster_loads.items()},
            'number_of_pods_pending': total_pending,
            'number_pending_public': round(pending_public, 3),
            'number_pending_private': round(pending_private, 3),
            'total_percent_pending': round(total_percent_pending, 3)
        }
    return processed_data

# Functions from processing.py
def process_resources(data, execution_mode='kwok'):
    """
    Calcula recursos alocados e requisitados para cada cluster.
    
    Args:
        data: Raw JSON data
        execution_mode: 'kwok' or 'real' (both use the same standardized calculation)
    """
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
            
            # Loads are percentages (0-1), multiply by capacity to get absolute values
            mem_allocated[label].append(mem_cap * min(mem_load, 1.0))
            cpu_allocated[label].append(cpu_cap * min(cpu_load, 1.0))
            
            # Requested: cpu_requested and memory_requested are also percentages (0-1)
            # Multiply by capacity to get absolute values (cores/GB)
            mem_requested_value = c['cluster_load'].get('memory_requested', 0)
            cpu_requested_value = c['cluster_load'].get('cpu_requested', 0)
            mem_requested[label].append(mem_cap * mem_requested_value if mem_requested_value > 0 else 0.0)
            cpu_requested[label].append(cpu_cap * cpu_requested_value if cpu_requested_value > 0 else 0.0)

        pods_sum_for_ts = {'public': 0, 'private': 0}
        for workload in data[ts_str].get('workloads', []):
            label = workload['cluster_label']
            pending_count = workload.get('pods_pending', 0)
            if label in pods_sum_for_ts:
                pods_sum_for_ts[label] += pending_count
        pending_pods['public'].append(pods_sum_for_ts['public'])
        pending_pods['private'].append(pods_sum_for_ts['private'])

    return timestamps, mem_allocated, mem_requested, cpu_allocated, cpu_requested, pending_pods

def process_cluster_info(data, timestamps, limit_load=True, execution_mode='kwok'):
    """
    Processes cluster info (limiting load or not).
    
    Args:
        data: Raw JSON data
        timestamps: List of timestamps
        limit_load: Whether to limit load to 1.0 (for allocated metrics)
        execution_mode: 'kwok' or 'real' (both use the same standardized calculation)
    """
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
            
            # Limit load to 1.0 when requested (for allocated metrics)
            if limit_load:
                mem_load = min(mem_load, 1.0)
                cpu_load = min(cpu_load, 1.0)
            
            mem_cap = parse_resource_value(c['cluster_memory_capacity'], 'Mi') / 1024
            cpu_cap = parse_resource_value(c['cluster_cpu_capacity'], 'm') / 1000
            
            if c['cluster_label'] == 'public':
                # Load is percentage (0-1), multiply by capacity
                result['mem_load_public'].append(mem_load * mem_cap)
                result['cpu_load_public'].append(cpu_load * cpu_cap)
                result['cpu_capacity_public'].append(cpu_cap)
                result['memory_capacity_public'].append(mem_cap)
            
            elif c['cluster_label'] == 'private':
                # Load is percentage (0-1), multiply by capacity
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


def process_network_io_data(data, timestamps, execution_mode='kwok'):
    """
    Process network and I/O metrics from cluster info.
    Only processes in REAL mode (when execution_mode='real').
    
    Args:
        data: Raw JSON data
        timestamps: List of timestamps
        execution_mode: 'kwok' or 'real' (only processes if 'real')
        
    Returns:
        Dictionary with network and I/O data by cluster
    """
    if execution_mode != 'real':
        # Return empty data for KWOK mode
        return {
            'network_receive_public': [],
            'network_receive_private': [],
            'network_transmit_public': [],
            'network_transmit_private': [],
            'io_read_public': [],
            'io_read_private': [],
            'io_write_public': [],
            'io_write_private': []
        }
    
    result = {
        'network_receive_public': [],
        'network_receive_private': [],
        'network_transmit_public': [],
        'network_transmit_private': [],
        'io_read_public': [],
        'io_read_private': [],
        'io_write_public': [],
        'io_write_private': []
    }
    
    for ts in timestamps:
        ts_str = str(ts)
        
        # Initialize with zeros
        for key in result:
            result[key].append(0.0)
        
        for c in data[ts_str].get('cluster_info', []):
            cluster_load = c.get('cluster_load', {})
            network_receive = cluster_load.get('network_receive', 0.0)
            network_transmit = cluster_load.get('network_transmit', 0.0)
            io_read = cluster_load.get('io_read', 0.0)
            io_write = cluster_load.get('io_write', 0.0)
            
            label = c.get('cluster_label')
            if label == 'public':
                result['network_receive_public'][-1] = network_receive
                result['network_transmit_public'][-1] = network_transmit
                result['io_read_public'][-1] = io_read
                result['io_write_public'][-1] = io_write
            elif label == 'private':
                result['network_receive_private'][-1] = network_receive
                result['network_transmit_private'][-1] = network_transmit
                result['io_read_private'][-1] = io_read
                result['io_write_private'][-1] = io_write
    
    return result

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

def extract_interval_duration(raw_data: Dict[str, Any]) -> int:
    """
    Extract interval duration from raw data.
    Looks for interval_duration in the first timestamp's data.
    
    Args:
        raw_data: Raw JSON data
        
    Returns:
        Interval duration in seconds (default: 30)
    """
    if not raw_data:
        return 30
    
    # Try to get from first timestamp
    first_ts = sorted(raw_data.keys())[0]
    first_data = raw_data[first_ts]
    
    # Check cluster_info for interval_duration
    if 'cluster_info' in first_data and first_data['cluster_info']:
        cluster = first_data['cluster_info'][0]
        if 'interval_duration' in cluster:
            return int(str(cluster['interval_duration']).rstrip('s'))
    
    # Check workloads for interval_duration
    if 'workloads' in first_data and first_data['workloads']:
        workload = first_data['workloads'][0]
        if 'pricing' in workload and 'interval_duration' in workload['pricing']:
            return int(str(workload['pricing']['interval_duration']).rstrip('s'))
    
    return 30  # Default


def process_cluster_metrics_at_timestamp(
    cluster_data: Dict[str, Any],
    timestamp: int,
    execution_mode: str = 'kwok'
) -> ClusterMetrics:
    """
    Process cluster metrics at a specific timestamp.
    
    Args:
        cluster_data: Raw cluster data from JSON
        timestamp: Unix timestamp
        execution_mode: 'kwok' (percentual 0-1) or 'real' (valores absolutos do cAdvisor)
        
    Returns:
        ClusterMetrics object
    """
    label = cluster_data['cluster_label']
    
    # Parse capacities
    mem_cap = parse_resource_value(cluster_data.get('cluster_memory_capacity', '0Mi'), 'Mi') / 1024
    cpu_cap = parse_resource_value(cluster_data.get('cluster_cpu_capacity', '0m'), 'm') / 1000
    
    # Get loads
    cluster_load = cluster_data.get('cluster_load', {})
    mem_load = cluster_load.get('memory', 0.0)
    cpu_load = cluster_load.get('cpu', 0.0)
    mem_load_requested = cluster_load.get('memory_requested', 0.0)
    cpu_load_requested = cluster_load.get('cpu_requested', 0.0)
    
    # Calculate allocated and requested resources
    # Loads are percentages (0-1), multiply by capacity to get absolute values
    mem_allocated = mem_cap * min(mem_load, 1.0)
    cpu_allocated = cpu_cap * min(cpu_load, 1.0)
    
    # cpu_requested and memory_requested are also percentages (0-1) from the monitor
    # Multiply by capacity to get absolute values (cores/GB)
    mem_requested = mem_cap * mem_load_requested if mem_load_requested > 0 else 0.0
    cpu_requested = cpu_cap * cpu_load_requested if cpu_load_requested > 0 else 0.0
    
    # Get node information
    node_info = cluster_data.get('node_info', {})
    node_cpu = int(node_info.get('cpu', 0))
    node_memory = int(node_info.get('memory', 0))
    node_quantity = int(node_info.get('quantity', 1) or 1)
    
    # If node_info is missing, try to estimate from capacity
    if node_cpu == 0 or node_memory == 0:
        if node_quantity > 0 and cpu_cap > 0 and mem_cap > 0:
            node_cpu = int(cpu_cap / node_quantity)
            node_memory = int(mem_cap / node_quantity)
    
    return ClusterMetrics(
        label=label,
        timestamp=timestamp,
        cpu_capacity=cpu_cap,
        memory_capacity=mem_cap,
        cpu_allocated=cpu_allocated,
        memory_allocated=mem_allocated,
        cpu_requested=cpu_requested,
        memory_requested=mem_requested,
        cpu_load=cpu_load,
        memory_load=mem_load,
        cpu_load_requested=cpu_load_requested,
        memory_load_requested=mem_load_requested,
        pending_pods=0,  # Will be updated later
        node_cpu=node_cpu,
        node_memory=node_memory,
        node_quantity=node_quantity
    )


def process_pricing_metrics_at_timestamp(
    cluster_data: Dict[str, Any],
    timestamp: int,
    interval_duration: int
) -> PricingMetrics:
    """
    Process pricing information for a single cluster at a specific timestamp.
    
    Args:
        cluster_data: Raw cluster data from JSON
        timestamp: Unix timestamp
        interval_duration: Interval duration in seconds
        
    Returns:
        PricingMetrics object
    """
    label = cluster_data['cluster_label']
    
    # Get node information
    node_info = cluster_data.get('node_info', {})
    node_cpu = int(node_info.get('cpu', 0))
    node_memory = int(node_info.get('memory', 0))
    node_quantity = int(node_info.get('quantity', 1) or 1)
    
    # If node_info is missing, try to estimate from capacity
    if node_cpu == 0 or node_memory == 0:
        cpu_cap_str = cluster_data.get('cluster_cpu_capacity', '0m')
        mem_cap_str = cluster_data.get('cluster_memory_capacity', '0Mi')
        
        total_cpu = parse_millicores_to_cores(cpu_cap_str)
        total_memory = parse_mebibytes_to_gb(mem_cap_str)
        
        if node_quantity > 0 and total_cpu > 0 and total_memory > 0:
            node_cpu = int(total_cpu / node_quantity)
            node_memory = int(total_memory / node_quantity)
    
    # Calculate cost
    if node_cpu > 0 and node_memory > 0:
        cost_info = calculate_infrastructure_cost(
            node_cpu=node_cpu,
            node_memory=node_memory,
            node_quantity=node_quantity,
            interval_seconds=interval_duration
        )
        
        return PricingMetrics(
            label=label,
            timestamp=timestamp,
            cost_per_interval=cost_info['cost_per_interval'],
            hourly_cost=cost_info['hourly_cost'],
            instance_type=cost_info.get('instance_type'),
            provider=cost_info.get('provider')
        )
    else:
        return PricingMetrics(
            label=label,
            timestamp=timestamp,
            cost_per_interval=0.0,
            hourly_cost=0.0,
            instance_type=None,
            provider=None
        )


def process_pricing_data(data, execution_mode='kwok'):
    """
    Process pricing information for all clusters across all timestamps.
    
    Args:
        data: Raw JSON data
        execution_mode: 'kwok' or 'real' (not used but kept for compatibility)
        
    Returns:
        Tuple of (timestamps, pricing_data_dict)
        pricing_data_dict: {timestamp: {label: PricingMetrics}}
    """
    timestamps = sorted([int(ts) for ts in data.keys()])
    interval_duration = extract_interval_duration(data)
    pricing_data = {}
    
    for ts in timestamps:
        ts_str = str(ts)
        ts_data = data[ts_str]
        pricing_data[ts] = {}
        
        for cluster_data in ts_data.get('cluster_info', []):
            pricing_metric = process_pricing_metrics_at_timestamp(
                cluster_data, ts, interval_duration
            )
            pricing_data[ts][pricing_metric.label] = pricing_metric
    
    return timestamps, pricing_data


def process_workload_metrics_at_timestamp(
    workloads: List[Dict[str, Any]],
    timestamp: int
) -> WorkloadMetrics:
    """
    Process workload information at a specific timestamp.
    
    Args:
        workloads: List of workload data from JSON
        timestamp: Unix timestamp
        
    Returns:
        WorkloadMetrics object
    """
    total_pods = 0
    total_pending = 0
    pending_public = 0
    pending_private = 0
    
    for workload in workloads:
        total_pods += workload.get('pods_total', 0)
        pending = workload.get('pods_pending', 0)
        total_pending += pending
        
        cluster_label = workload.get('cluster_label', '')
        if cluster_label == 'private':
            pending_private += pending
        else:
            pending_public += pending
    
    total_percent_pending = (total_pending / total_pods) if total_pods > 0 else 0.0
    
    return WorkloadMetrics(
        timestamp=timestamp,
        total_pending=total_pending,
        pending_public=pending_public,
        pending_private=pending_private,
        total_percent_pending=total_percent_pending
    )


def update_pending_pods_in_clusters(
    cluster_metrics: Dict[int, List[ClusterMetrics]],
    workload_metrics: Dict[int, WorkloadMetrics]
):
    """
    Update pending_pods count in ClusterMetrics based on WorkloadMetrics.
    Modifies cluster_metrics in place.
    """
    for timestamp, workload in workload_metrics.items():
        if timestamp in cluster_metrics:
            for cluster in cluster_metrics[timestamp]:
                if cluster.label == 'private':
                    cluster.pending_pods = workload.pending_private
                elif cluster.label == 'public':
                    cluster.pending_pods = workload.pending_public


def process_migration_events(migration_df) -> List[MigrationEvent]:
    """
    Convert migration DataFrame to list of MigrationEvent objects.
    
    Args:
        migration_df: DataFrame from parse_migration_logs
        
    Returns:
        List of MigrationEvent objects
    """
    if migration_df is None or migration_df.empty:
        return []
    
    events = []
    for _, row in migration_df.iterrows():
        events.append(MigrationEvent(
            timestamp=int(row['timestamp']),
            execution=int(row['execution']),
            type=str(row['type']),
            total_migrated_pods=int(row['total_migrated_pods']),
            migrated_to_private=int(row['migrated_to_private']),
            migrated_to_public=int(row['migrated_to_public'])
        ))
    
    return events


def process_simulation_data(
    raw_data: Dict[str, Any],
    migration_df=None,
    run_name: str = "unknown",
    execution_mode: str = 'kwok'
) -> ProcessedSimulationData:
    """
    Process complete simulation data from raw JSON.
    
    This is the main processing function that converts raw data into
    structured ProcessedSimulationData.
    
    Args:
        raw_data: Raw metrics JSON data
        migration_df: Optional DataFrame with migration events
        run_name: Name of the simulation run (usually timestamp)
        
    Returns:
        ProcessedSimulationData object with all processed metrics
    """
    # Extract basic information
    timestamps = sorted([int(ts) for ts in raw_data.keys()])
    interval_duration = extract_interval_duration(raw_data)
    
    # Initialize collections
    cluster_metrics = {}
    pricing_metrics = {}
    workload_metrics = {}
    
    # Process each timestamp
    for ts in timestamps:
        ts_str = str(ts)
        ts_data = raw_data[ts_str]
        
        # Process cluster data
        cluster_info_list = ts_data.get('cluster_info', [])
        cluster_metrics[ts] = []
        pricing_metrics[ts] = []
        
        for cluster_data in cluster_info_list:
            # Process cluster metrics
            cluster_metric = process_cluster_metrics_at_timestamp(cluster_data, ts, execution_mode)
            cluster_metrics[ts].append(cluster_metric)
            
            # Process pricing metrics
            pricing_metric = process_pricing_metrics_at_timestamp(
                cluster_data, ts, interval_duration
            )
            pricing_metrics[ts].append(pricing_metric)
        
        # Process workload data
        workloads = ts_data.get('workloads', [])
        workload_metrics[ts] = process_workload_metrics_at_timestamp(workloads, ts)
    
    # Update pending pods in cluster metrics
    update_pending_pods_in_clusters(cluster_metrics, workload_metrics)
    
    # Process migration events
    migration_events = process_migration_events(migration_df)
    
    return ProcessedSimulationData(
        run_name=run_name,
        interval_duration=interval_duration,
        timestamps=timestamps,
        cluster_metrics=cluster_metrics,
        pricing_metrics=pricing_metrics,
        workload_metrics=workload_metrics,
        migration_events=migration_events
    )
