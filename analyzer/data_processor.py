"""
Data Processor (Refactored)

This module processes raw JSON data from simulations and converts it into
structured data models. It focuses purely on data transformation without
any visualization concerns.
"""

from typing import Dict, Any, List
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


def extract_interval_duration(raw_data: Dict[str, Any]) -> int:
    """Extract interval duration from raw data."""
    timestamps = sorted([int(ts) for ts in raw_data.keys()])
    if not timestamps:
        return 30  # Default
    
    first_ts = str(timestamps[0])
    if 'interval_duration' in raw_data.get(first_ts, {}):
        interval_str = raw_data[first_ts].get('interval_duration', '30s')
        try:
            return int(str(interval_str).rstrip('s'))
        except Exception:
            return 30
    return 30


def process_cluster_metrics_at_timestamp(
    cluster_data: Dict[str, Any],
    timestamp: int
) -> ClusterMetrics:
    """
    Process cluster information for a single cluster at a specific timestamp.
    
    Args:
        cluster_data: Raw cluster data from JSON
        timestamp: Unix timestamp
        
    Returns:
        ClusterMetrics object
    """
    label = cluster_data['cluster_label']
    
    # Parse capacity
    cpu_capacity = parse_resource_value(cluster_data['cluster_cpu_capacity'], 'm') / 1000.0
    memory_capacity = parse_resource_value(cluster_data['cluster_memory_capacity'], 'Mi') / 1024.0
    
    # Get load information
    cluster_load = cluster_data.get('cluster_load', {})
    cpu_load = cluster_load.get('cpu', 0.0)
    memory_load = cluster_load.get('memory', 0.0)
    cpu_load_requested = cluster_load.get('cpu_requested', 0.0)
    memory_load_requested = cluster_load.get('memory_requested', 0.0)
    
    # Calculate allocated and requested resources
    cpu_allocated = cpu_capacity * cpu_load
    memory_allocated = memory_capacity * memory_load
    cpu_requested = cpu_capacity * cpu_load_requested
    memory_requested = memory_capacity * memory_load_requested
    
    # Node information
    node_info = cluster_data.get('node_info', {})
    node_cpu = int(node_info.get('cpu', 0))
    node_memory = int(node_info.get('memory', 0))
    node_quantity = int(node_info.get('quantity', 1) or 1)
    
    # If node_info is missing, estimate from capacity
    if node_cpu == 0 or node_memory == 0:
        if node_quantity > 0 and cpu_capacity > 0 and memory_capacity > 0:
            node_cpu = int(cpu_capacity / node_quantity)
            node_memory = int(memory_capacity / node_quantity)
    
    return ClusterMetrics(
        label=label,
        timestamp=timestamp,
        cpu_capacity=cpu_capacity,
        memory_capacity=memory_capacity,
        cpu_allocated=cpu_allocated,
        memory_allocated=memory_allocated,
        cpu_requested=cpu_requested,
        memory_requested=memory_requested,
        cpu_load=cpu_load,
        memory_load=memory_load,
        cpu_load_requested=cpu_load_requested,
        memory_load_requested=memory_load_requested,
        pending_pods=0,  # Will be updated from workload data
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
    run_name: str = "unknown"
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
            cluster_metric = process_cluster_metrics_at_timestamp(cluster_data, ts)
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
