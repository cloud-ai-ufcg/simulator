"""
Plot Data Builder

This module transforms processed simulation data into pandas DataFrames
specifically formatted for visualization. It acts as an intermediary layer
between data processing and plotting.
"""

import pandas as pd
from typing import List, Tuple
from data_models import ProcessedSimulationData, MigrationEvent


def build_resource_dataframe(data: ProcessedSimulationData) -> pd.DataFrame:
    """
    Build a DataFrame containing resource metrics for all clusters over time.
    
    Returns DataFrame with columns:
    - timestamp: pandas datetime
    - time_seconds: seconds from start
    - mem_allocated_public, mem_allocated_private
    - mem_requested_public, mem_requested_private
    - cpu_allocated_public, cpu_allocated_private
    - cpu_requested_public, cpu_requested_private
    - number_pending_public, number_pending_private
    - cluster_mem_load_public, cluster_mem_load_private
    - cluster_cpu_load_public, cluster_cpu_load_private
    - cluster_cpu_capacity_public, cluster_cpu_capacity_private
    - cluster_memory_capacity_public, cluster_memory_capacity_private
    """
    timestamps = data.get_timestamps_sorted()
    
    records = []
    for ts in timestamps:
        record = {'timestamp': pd.to_datetime(ts, unit='s')}
        
        # Get cluster metrics for both clusters
        for label in ['public', 'private']:
            cluster = data.get_cluster_by_label(ts, label)
            workload = data.workload_metrics.get(ts)
            
            if cluster:
                record[f'mem_allocated_{label}'] = cluster.memory_allocated
                record[f'mem_requested_{label}'] = cluster.memory_requested
                record[f'cpu_allocated_{label}'] = cluster.cpu_allocated
                record[f'cpu_requested_{label}'] = cluster.cpu_requested
                record[f'cluster_mem_load_{label}'] = cluster.memory_load * cluster.memory_capacity
                record[f'cluster_cpu_load_{label}'] = cluster.cpu_load * cluster.cpu_capacity
                record[f'cluster_cpu_capacity_{label}'] = cluster.cpu_capacity
                record[f'cluster_memory_capacity_{label}'] = cluster.memory_capacity
            else:
                # Fill with zeros if cluster data is missing
                record[f'mem_allocated_{label}'] = 0.0
                record[f'mem_requested_{label}'] = 0.0
                record[f'cpu_allocated_{label}'] = 0.0
                record[f'cpu_requested_{label}'] = 0.0
                record[f'cluster_mem_load_{label}'] = 0.0
                record[f'cluster_cpu_load_{label}'] = 0.0
                record[f'cluster_cpu_capacity_{label}'] = 0.0
                record[f'cluster_memory_capacity_{label}'] = 0.0
            
            # Add pending pods
            if workload:
                if label == 'public':
                    record[f'number_pending_{label}'] = workload.pending_public
                else:
                    record[f'number_pending_{label}'] = workload.pending_private
            else:
                record[f'number_pending_{label}'] = 0
        
        records.append(record)
    
    df = pd.DataFrame(records)
    
    # Add time_seconds column
    if not df.empty:
        start_time = df['timestamp'].min()
        df['time_seconds'] = (df['timestamp'] - start_time).dt.total_seconds()
    else:
        df['time_seconds'] = pd.Series(dtype='float64')
    
    return df


def build_load_dataframe(data: ProcessedSimulationData) -> pd.DataFrame:
    """
    Build a DataFrame containing cluster load metrics over time.
    
    Returns DataFrame with columns:
    - timestamp: pandas datetime
    - time_seconds: seconds from start
    - cpu_load_private, cpu_load_public
    - mem_load_private, mem_load_public
    - number_of_pods_pending
    - number_pending_private, number_pending_public
    - total_percent_pending
    """
    timestamps = data.get_timestamps_sorted()
    
    records = []
    for ts in timestamps:
        workload = data.workload_metrics.get(ts)
        
        record = {
            'timestamp': pd.to_datetime(ts, unit='s'),
            'number_of_pods_pending': workload.total_pending if workload else 0,
            'number_pending_private': workload.pending_private if workload else 0,
            'number_pending_public': workload.pending_public if workload else 0,
            'total_percent_pending': workload.total_percent_pending if workload else 0.0,
        }
        
        # Add cluster loads (as percentages/fractions, not absolute values)
        for label in ['public', 'private']:
            cluster = data.get_cluster_by_label(ts, label)
            if cluster:
                record[f'cpu_load_{label}'] = cluster.cpu_load
                record[f'mem_load_{label}'] = cluster.memory_load
            else:
                record[f'cpu_load_{label}'] = 0.0
                record[f'mem_load_{label}'] = 0.0
        
        records.append(record)
    
    df = pd.DataFrame(records)
    
    # Add time_seconds column
    if not df.empty:
        start_time = df['timestamp'].min()
        df['time_seconds'] = (df['timestamp'] - start_time).dt.total_seconds()
    else:
        df['time_seconds'] = pd.Series(dtype='float64')
    
    return df


def build_pricing_dataframe(data: ProcessedSimulationData) -> Tuple[pd.DataFrame, dict]:
    """
    Build a DataFrame containing pricing metrics over time.
    
    Returns:
        Tuple of (DataFrame, instance_types_dict)
        
    DataFrame with columns:
    - timestamp: pandas datetime
    - time_seconds: seconds from start
    - cost_public, cost_private, cost_total
    - cost_public_hourly, cost_private_hourly
    - cumulative_cost_public, cumulative_cost_private, cumulative_cost_total
    
    instance_types_dict: {'public': 'instance_type', 'private': 'instance_type'}
    """
    timestamps = data.get_timestamps_sorted()
    instance_types = {}
    
    records = []
    for ts in timestamps:
        record = {'timestamp': pd.to_datetime(ts, unit='s')}
        
        total_cost = 0.0
        for label in ['public', 'private']:
            pricing = data.get_pricing_by_label(ts, label)
            if pricing:
                record[f'cost_{label}'] = pricing.cost_per_interval
                record[f'cost_{label}_hourly'] = pricing.hourly_cost
                total_cost += pricing.cost_per_interval
                
                # Store instance type (first occurrence)
                if label not in instance_types and pricing.instance_type:
                    instance_types[label] = pricing.instance_type
            else:
                record[f'cost_{label}'] = 0.0
                record[f'cost_{label}_hourly'] = 0.0
        
        record['cost_total'] = total_cost
        records.append(record)
    
    df = pd.DataFrame(records)
    
    # Add time_seconds column
    if not df.empty:
        start_time = df['timestamp'].min()
        df['time_seconds'] = (df['timestamp'] - start_time).dt.total_seconds()
        
        # Calculate cumulative costs
        df['cumulative_cost_public'] = df['cost_public'].cumsum()
        df['cumulative_cost_private'] = df['cost_private'].cumsum()
        df['cumulative_cost_total'] = df['cost_total'].cumsum()
    else:
        df['time_seconds'] = pd.Series(dtype='float64')
        df['cumulative_cost_public'] = pd.Series(dtype='float64')
        df['cumulative_cost_private'] = pd.Series(dtype='float64')
        df['cumulative_cost_total'] = pd.Series(dtype='float64')
    
    return df, instance_types


def build_migration_dataframe(migration_events: List[MigrationEvent]) -> pd.DataFrame:
    """
    Build a DataFrame containing migration events.
    
    Returns DataFrame with columns:
    - execution, type, timestamp, total_migrated_pods, 
      migrated_to_private, migrated_to_public
    """
    if not migration_events:
        return pd.DataFrame(columns=[
            'execution', 'type', 'timestamp', 'total_migrated_pods',
            'migrated_to_private', 'migrated_to_public'
        ])
    
    records = []
    for event in migration_events:
        records.append({
            'execution': event.execution,
            'type': event.type,
            'timestamp': event.timestamp,
            'total_migrated_pods': event.total_migrated_pods,
            'migrated_to_private': event.migrated_to_private,
            'migrated_to_public': event.migrated_to_public
        })
    
    return pd.DataFrame(records)


def build_summary_input_data(data: ProcessedSimulationData) -> Tuple[dict, dict]:
    """
    Build data structures needed for summary statistics generation.
    
    Returns:
        Tuple of (grouped_data, migration_dict)
        
    grouped_data format:
        {
            'workloads': [[workload_dict, ...], ...],  # One list per timestamp
            'cluster_info': [[cluster_dict, ...], ...]  # One list per timestamp
        }
    """
    timestamps = data.get_timestamps_sorted()
    
    grouped_workloads = []
    grouped_clusters = []
    
    for ts in timestamps:
        # Reconstruct workload dicts for this timestamp
        workload = data.workload_metrics.get(ts)
        if workload:
            # Create workload entries (simplified representation)
            workloads_at_ts = []
            
            # Add entries for each cluster
            for label in ['public', 'private']:
                cluster = data.get_cluster_by_label(ts, label)
                if cluster:
                    pending = workload.pending_private if label == 'private' else workload.pending_public
                    # Create a representative workload dict
                    workloads_at_ts.append({
                        'cluster_label': label,
                        'pods_pending': pending,
                        'pods_total': 1  # Placeholder, actual value not stored in new model
                    })
            
            grouped_workloads.append(workloads_at_ts)
        
        # Reconstruct cluster info dicts
        clusters_at_ts = []
        for label in ['public', 'private']:
            cluster = data.get_cluster_by_label(ts, label)
            if cluster:
                cluster_dict = {
                    'cluster_label': label,
                    'cluster_cpu_capacity': f'{int(cluster.cpu_capacity * 1000)}m',
                    'cluster_memory_capacity': f'{int(cluster.memory_capacity * 1024)}Mi',
                    'cluster_load': {
                        'cpu': cluster.cpu_load,
                        'memory': cluster.memory_load,
                        'cpu_requested': cluster.cpu_load_requested,
                        'memory_requested': cluster.memory_load_requested
                    },
                    'node_info': {
                        'cpu': cluster.node_cpu,
                        'memory': cluster.node_memory,
                        'quantity': cluster.node_quantity
                    }
                }
                clusters_at_ts.append(cluster_dict)
        
        grouped_clusters.append(clusters_at_ts)
    
    grouped_data = {
        'workloads': grouped_workloads,
        'cluster_info': grouped_clusters
    }
    
    return grouped_data, data.interval_duration
