"""
Data Models for Analyzer

This module defines data structures to represent processed simulation metrics.
These models are independent of visualization logic and provide a clean interface
between data processing and plotting.
"""

from dataclasses import dataclass, field
from typing import Dict, List, Optional
from datetime import datetime


@dataclass
class ClusterMetrics:
    """Metrics for a single cluster at a specific timestamp."""
    label: str  # 'public' or 'private'
    timestamp: int  # Unix timestamp
    
    # Resource capacity
    cpu_capacity: float  # Total CPU in cores
    memory_capacity: float  # Total memory in GB
    
    # Resource usage (allocated)
    cpu_allocated: float  # CPU allocated in cores
    memory_allocated: float  # Memory allocated in GB
    
    # Resource usage (requested)
    cpu_requested: float  # CPU requested in cores
    memory_requested: float  # Memory requested in GB
    
    # Load percentages
    cpu_load: float  # 0.0 to 1.0+ (can exceed 1.0)
    memory_load: float  # 0.0 to 1.0+ (can exceed 1.0)
    cpu_load_requested: float  # 0.0 to 1.0+
    memory_load_requested: float  # 0.0 to 1.0+
    
    # Pending pods
    pending_pods: int
    
    # Node information
    node_cpu: int  # vCPUs per node
    node_memory: int  # Memory GB per node
    node_quantity: int  # Number of nodes


@dataclass
class PricingMetrics:
    """Pricing information for a cluster at a specific timestamp."""
    label: str  # 'public' or 'private'
    timestamp: int  # Unix timestamp
    
    # Cost information
    cost_per_interval: float  # Cost in USD for this interval
    hourly_cost: float  # Hourly cost in USD
    
    # Instance information
    instance_type: Optional[str] = None
    provider: Optional[str] = None


@dataclass
class WorkloadMetrics:
    """Metrics for workloads at a specific timestamp."""
    timestamp: int  # Unix timestamp
    
    # Pending pods summary
    total_pending: int
    pending_public: int
    pending_private: int
    total_percent_pending: float  # 0.0 to 1.0


@dataclass
class MigrationEvent:
    """Represents a single migration event."""
    timestamp: int  # Unix timestamp
    execution: int  # Migration execution number
    type: str  # 'public', 'private', 'both', 'no migration'
    total_migrated_pods: int
    migrated_to_private: int
    migrated_to_public: int


@dataclass
class ProcessedSimulationData:
    """
    Complete processed simulation data.
    This is the main output from data processing, ready for analysis or visualization.
    """
    # Metadata
    run_name: str  # Timestamp folder name
    interval_duration: int  # Interval in seconds (e.g., 30)
    
    # Time series data
    timestamps: List[int]  # All unique timestamps
    
    # Cluster metrics by timestamp
    cluster_metrics: Dict[int, List[ClusterMetrics]]  # timestamp -> list of clusters
    
    # Pricing metrics by timestamp
    pricing_metrics: Dict[int, List[PricingMetrics]]  # timestamp -> list of clusters
    
    # Workload metrics by timestamp
    workload_metrics: Dict[int, WorkloadMetrics]  # timestamp -> workload data
    
    # Migration events
    migration_events: List[MigrationEvent] = field(default_factory=list)
    
    def get_cluster_by_label(self, timestamp: int, label: str) -> Optional[ClusterMetrics]:
        """Get cluster metrics for a specific timestamp and label."""
        if timestamp not in self.cluster_metrics:
            return None
        for cluster in self.cluster_metrics[timestamp]:
            if cluster.label == label:
                return cluster
        return None
    
    def get_pricing_by_label(self, timestamp: int, label: str) -> Optional[PricingMetrics]:
        """Get pricing metrics for a specific timestamp and label."""
        if timestamp not in self.pricing_metrics:
            return None
        for pricing in self.pricing_metrics[timestamp]:
            if pricing.label == label:
                return pricing
        return None
    
    def get_timestamps_sorted(self) -> List[int]:
        """Get timestamps in chronological order."""
        return sorted(self.timestamps)
    
    def get_total_cost_at_timestamp(self, timestamp: int) -> float:
        """Get total cost across all clusters at a timestamp."""
        if timestamp not in self.pricing_metrics:
            return 0.0
        return sum(p.cost_per_interval for p in self.pricing_metrics[timestamp])
    
    def get_cumulative_cost_by_label(self, label: str) -> float:
        """Get cumulative cost for a specific cluster label."""
        total = 0.0
        for ts in self.get_timestamps_sorted():
            pricing = self.get_pricing_by_label(ts, label)
            if pricing:
                total += pricing.cost_per_interval
        return total
    
    def get_cumulative_cost_total(self) -> float:
        """Get total cumulative cost across all clusters."""
        return sum(self.get_total_cost_at_timestamp(ts) 
                   for ts in self.get_timestamps_sorted())


@dataclass
class SummaryStatistics:
    """Statistical summary of simulation metrics."""
    mean: float
    min: float
    max: float
    std: float
    median: float


@dataclass
class SimulationSummary:
    """
    Aggregated summary statistics for the entire simulation.
    """
    # Cost statistics
    cost: SummaryStatistics
    
    # Resource usage statistics
    cpu_usage: SummaryStatistics
    memory_usage: SummaryStatistics
    
    # Pending pods statistics
    pending_pods: SummaryStatistics
    time_with_pending: SummaryStatistics
    workloads_with_pending_pods: SummaryStatistics
    
    # Migration statistics
    number_of_migrations: SummaryStatistics
