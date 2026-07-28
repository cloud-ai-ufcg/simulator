"""
Data Processor (Refactored)

This module processes raw JSON data from simulations and converts it into
structured data models. It focuses purely on data transformation without
any visualization concerns.
"""

from typing import Dict, Any, List
from datetime import datetime
from data_models import (
    ClusterMetrics, PricingMetrics, WorkloadMetrics,
    MigrationEvent, ProcessedSimulationData, UnschedulableSnapshot
)
from utils import parse_resource_value
from pricing_utils import (
    calculate_infrastructure_cost,
    parse_millicores_to_cores,
    parse_mebibytes_to_gb
)


def resolve_cluster_label(cluster_data: Dict[str, Any]) -> str:
    """Resolve cluster label from old/new metrics formats."""
    label = cluster_data.get('cluster_label')
    if label in ['public', 'private']:
        return label

    profile = cluster_data.get('cluster_profile')
    if profile in ['public', 'private']:
        return profile

    cluster_id = str(cluster_data.get('cluster_id', '')).strip()
    if cluster_id == 'member1':
        return 'private'
    if cluster_id == 'member2':
        return 'public'

    return cluster_id or 'public'


def parse_timestamp_key(ts_key: str) -> int:
    """
    Parse a timestamp key from metrics.json to Unix timestamp (int).
    
    Supports two formats:
    - Unix timestamp (int or string): '1732744377' or 1732744377
    - Date string: '2025-11-27 23:32:57'
    
    Args:
        ts_key: Timestamp key from JSON
        
    Returns:
        Unix timestamp as integer
    """
    ts_str = str(ts_key).strip()
    
    # Try to parse as integer (Unix timestamp)
    try:
        return int(ts_str)
    except ValueError:
        pass
    
    # Try to parse as date string 'YYYY-MM-DD HH:MM:SS'
    try:
        dt = datetime.strptime(ts_str, '%Y-%m-%d %H:%M:%S')
        return int(dt.timestamp())
    except ValueError:
        pass
    
    # Try other common formats
    for fmt in ['%Y/%m/%d %H:%M:%S', '%d-%m-%Y %H:%M:%S', '%Y-%m-%dT%H:%M:%S']:
        try:
            dt = datetime.strptime(ts_str, fmt)
            return int(dt.timestamp())
        except ValueError:
            continue
    
    raise ValueError(f"Unable to parse timestamp: {ts_key}")


def extract_interval_duration(raw_data: Dict[str, Any]) -> int:
    """Extract interval duration from raw data."""
    if not raw_data:
        return 30  # Default
    
    # Get the first key from raw_data (original format, not converted)
    first_key = next(iter(raw_data.keys()))
    if 'interval_duration' in raw_data.get(first_key, {}):
        interval_str = raw_data[first_key].get('interval_duration', '30s')
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
    label = resolve_cluster_label(cluster_data)
    
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
    label = resolve_cluster_label(cluster_data)
    
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
    timestamp: int,
    cluster_id_to_label: Dict[str, str]
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
        
        cluster_label = workload.get('cluster_label')
        if cluster_label not in ['public', 'private']:
            cluster_id = str(workload.get('cluster_id', '')).strip()
            cluster_label = cluster_id_to_label.get(cluster_id, 'public')
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


def process_unschedulable_events(unschedulable_df) -> List[UnschedulableSnapshot]:
    """Convert the unschedulable_bindings.jsonl DataFrame (from data_loader's
    load_unschedulable_data) into a list of UnschedulableSnapshot objects."""
    if unschedulable_df is None or unschedulable_df.empty:
        return []

    return [
        UnschedulableSnapshot(
            timestamp=int(row['timestamp']),
            count=int(row['unschedulable_count']),
            workload_ids=list(row['unschedulable_workloads']),
        )
        for _, row in unschedulable_df.iterrows()
    ]


def detect_migrations_from_snapshots(
    raw_data: Dict[str, Any],
    timestamps: List[int],
    unix_to_key: Dict[int, str],
) -> List[MigrationEvent]:
    """
    Fallback migration source for runs with no actuator activity at all
    (the Karmada-native baseline, where karmada-descheduler/scheduler
    rebalance workloads directly instead of the AI-driven actuator relabeling
    them — there is no actuator.log line to read in that case).

    Detects a migration whenever a workload's *set* of hosting clusters
    gains a cluster it wasn't already running on between two consecutive
    monitor snapshots — covers full moves and dynamic-weight rebalances
    alike, and (unlike comparing just the "dominant" cluster) isn't thrown
    off by workloads split exactly 50/50 across both clusters, which is the
    common case here: most multi-cluster splits in this data are tied pod
    counts, where "the dominant cluster" is arbitrary and flips on
    tie-breaking noise rather than a real move.

    Deliberately keyed off the *set* of clusters, not raw pod counts: a
    workload simply scaling up/down while staying on the same cluster(s)
    must not be counted as a migration. A workload's first-ever snapshot
    (still being created, reporting 0 pods everywhere) is also never treated
    as a prior placement — otherwise the jump from 0 to its steady-state
    replica count looks identical to a migration into that cluster and
    inflates the count with every fresh deployment. For the same reason, a
    workload that transiently drops to 0 pods everywhere (e.g. mid-rollout)
    keeps its last known non-empty placement on record rather than losing
    it, so a later reappearance on a *different* cluster is still correctly
    recognized as a migration instead of looking like a fresh deployment.

    Less precise than the actuator log (doesn't know pod-level counts, just
    which workloads changed), but it's the only signal metrics.json can
    offer when nothing else logged the change.

    Changes that land on the same timestamp are grouped into one
    MigrationEvent (one "execution"), mirroring how the actuator's own
    Migration Summary batches multiple relabels together.
    """
    cluster_id_to_label: Dict[str, str] = {}
    for key in unix_to_key.values():
        for cluster_data in raw_data[key].get('cluster_info', []):
            cluster_id = str(cluster_data.get('cluster_id', '')).strip()
            if cluster_id and cluster_id not in cluster_id_to_label:
                cluster_id_to_label[cluster_id] = resolve_cluster_label(cluster_data)
        if cluster_id_to_label:
            break

    # workload_id -> {cluster_label: pods} distribution as of its last
    # *non-empty* snapshot (see docstring for why empty ones are skipped
    # rather than stored).
    previous_distribution: Dict[str, Dict[str, int]] = {}
    # timestamp -> {'private': n, 'public': n} workloads that gained a new
    # hosting cluster, counted by which cluster(s) they moved to
    changes_by_ts: Dict[int, Dict[str, int]] = {}

    for ts in timestamps:
        workloads = raw_data[unix_to_key[ts]].get('workloads', [])
        pods_by_workload_cluster: Dict[str, Dict[str, int]] = {}
        for w in workloads:
            wid = w.get('workload_id')
            cluster_id = str(w.get('cluster_id', '')).strip()
            pods = w.get('pods_total', 0)
            if not wid or not cluster_id:
                continue
            label = cluster_id_to_label.get(cluster_id, cluster_id)
            pods_by_workload_cluster.setdefault(wid, {})[label] = pods

        for wid, by_label in pods_by_workload_cluster.items():
            distribution = {label: pods for label, pods in by_label.items() if pods > 0}
            if not distribution:
                # No running pods anywhere right now — don't overwrite the
                # last known real placement (see docstring).
                continue

            prev = previous_distribution.get(wid)
            if prev is not None:
                gained = sorted(
                    label for label in (set(distribution) - set(prev))
                    if label in ('private', 'public')
                )
                if gained:
                    changes_by_ts.setdefault(ts, {'private': 0, 'public': 0})
                    for label in gained:
                        changes_by_ts[ts][label] += 1
            previous_distribution[wid] = distribution

    events = []
    for execution, ts in enumerate(sorted(changes_by_ts.keys()), start=1):
        counts = changes_by_ts[ts]
        if counts['private'] and counts['public']:
            label_type = 'both'
        elif counts['private']:
            label_type = 'private'
        elif counts['public']:
            label_type = 'public'
        else:
            label_type = 'no migration'
        events.append(MigrationEvent(
            timestamp=ts,
            execution=execution,
            type=label_type,
            total_migrated_pods=counts['private'] + counts['public'],
            migrated_to_private=counts['private'],
            migrated_to_public=counts['public'],
        ))
    return events


def process_simulation_data(
    raw_data: Dict[str, Any],
    migration_df=None,
    run_name: str = "unknown",
    unschedulable_df=None,
) -> ProcessedSimulationData:
    """
    Process complete simulation data from raw JSON.

    This is the main processing function that converts raw data into
    structured ProcessedSimulationData.

    Args:
        raw_data: Raw metrics JSON data
        migration_df: Optional DataFrame with migration events
        run_name: Name of the simulation run (usually timestamp)
        unschedulable_df: Optional DataFrame from load_unschedulable_data

    Returns:
        ProcessedSimulationData object with all processed metrics
    """
    # Extract basic information
    # Create mapping from original keys to Unix timestamps
    key_to_unix = {key: parse_timestamp_key(key) for key in raw_data.keys()}
    timestamps = sorted(key_to_unix.values())
    unix_to_key = {v: k for k, v in key_to_unix.items()}
    
    interval_duration = extract_interval_duration(raw_data)
    
    # Initialize collections
    cluster_metrics = {}
    pricing_metrics = {}
    workload_metrics = {}
    
    # Process each timestamp
    for ts in timestamps:
        original_key = unix_to_key[ts]
        ts_data = raw_data[original_key]
        
        # Process cluster data
        cluster_info_list = ts_data.get('cluster_info', [])
        cluster_metrics[ts] = []
        pricing_metrics[ts] = []
        
        cluster_id_to_label = {}
        for cluster_data in cluster_info_list:
            cluster_id = str(cluster_data.get('cluster_id', '')).strip()
            if cluster_id:
                cluster_id_to_label[cluster_id] = resolve_cluster_label(cluster_data)

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
        workload_metrics[ts] = process_workload_metrics_at_timestamp(
            workloads, ts, cluster_id_to_label
        )
    
    # Update pending pods in cluster metrics
    update_pending_pods_in_clusters(cluster_metrics, workload_metrics)
    
    # Process migration events — prefer the actuator log (ground truth of
    # what was actually applied); fall back to detecting rebalances directly
    # from the metrics.json snapshots when there's no actuator activity at
    # all (e.g. the Karmada-native baseline).
    migration_events = process_migration_events(migration_df)
    if not migration_events:
        migration_events = detect_migrations_from_snapshots(raw_data, timestamps, unix_to_key)
        if migration_events:
            print(f"  (no actuator migrations found — {len(migration_events)} "
                  f"rebalance(s) inferred from metrics.json instead)")

    unschedulable_snapshots = process_unschedulable_events(unschedulable_df)

    return ProcessedSimulationData(
        run_name=run_name,
        interval_duration=interval_duration,
        timestamps=timestamps,
        cluster_metrics=cluster_metrics,
        pricing_metrics=pricing_metrics,
        workload_metrics=workload_metrics,
        migration_events=migration_events,
        unschedulable_snapshots=unschedulable_snapshots,
    )
