"""
Pricing Utility Functions
Functions for calculating infrastructure and workload costs.
Same logic as used in the AI Engine.
"""

from typing import Dict, Any, Optional
from pricing_data import aws_instance_types


def parse_mebibytes_to_gb(value) -> float:
    """
    Convert Kubernetes memory units to GB.
    
    Args:
        value: Memory value as string (e.g., "4096Mi", "16Gi") or numeric
        
    Returns:
        Memory in GB as float
    """
    if isinstance(value, (int, float)):
        return float(value)
    s = str(value).lower()
    try:
        if s.endswith("mi"):
            return float(s[:-2]) / 1024.0
        if s.endswith("gi"):
            return float(s[:-2])
        return float(s)
    except Exception:
        return 0.0


def parse_millicores_to_cores(value) -> float:
    """
    Convert Kubernetes CPU units to cores.
    
    Args:
        value: CPU value as string (e.g., "2000m", "4") or numeric
        
    Returns:
        CPU in cores as float
    """
    if isinstance(value, (int, float)):
        return float(value)
    s = str(value)
    if s.endswith("m"):
        try:
            return float(s[:-1]) / 1000.0
        except Exception:
            return 0.0
    try:
        return float(s)
    except Exception:
        return 0.0


def find_minimum_viable_instance(required_cpu: int, required_memory: int) -> Optional[Dict[str, Any]]:
    """
    Find the minimum viable AWS instance type that meets or exceeds the required CPU and memory.
    
    If no single instance meets the requirements, uses the largest available instance
    and scales the cost proportionally.
    
    Args:
        required_cpu: Required number of vCPUs
        required_memory: Required memory in GB
        
    Returns:
        Dict containing instance information with potentially adjusted price, or None if no instances available
    """
    # Try to find an instance that meets requirements
    for instance in aws_instance_types:
        if instance["vcpus"] >= required_cpu and instance["memory_gb"] >= required_memory:
            return instance
    
    # If no single instance meets requirements, use the largest available and scale proportionally
    largest_instance = None
    for instance in aws_instance_types:
        if largest_instance is None:
            largest_instance = instance
        elif instance["vcpus"] > largest_instance["vcpus"]:
            largest_instance = instance
    
    if largest_instance:
        # Calculate scaling factor based on CPU requirement
        cpu_scale = max(1.0, required_cpu / largest_instance["vcpus"])
        memory_scale = max(1.0, required_memory / largest_instance["memory_gb"])
        scale_factor = max(cpu_scale, memory_scale)
        
        # Return scaled instance info
        return {
            "name": f"{largest_instance['name']} (scaled {scale_factor:.2f}x)",
            "vcpus": largest_instance["vcpus"],
            "memory_gb": largest_instance["memory_gb"],
            "price_usd_per_hour": largest_instance["price_usd_per_hour"] * scale_factor,
            "provider": largest_instance["provider"]
        }
    
    # No instances available at all
    return None


def calculate_infrastructure_cost(
    node_cpu: int,
    node_memory: int,
    node_quantity: int,
    interval_seconds: int = 30
) -> Dict[str, Any]:
    """
    Calculate infrastructure cost for a cluster based on node specifications.
    
    Args:
        node_cpu: Number of vCPUs per node
        node_memory: Memory in GB per node
        node_quantity: Number of nodes in the cluster
        interval_seconds: Duration of the interval in seconds (default: 30)
        
    Returns:
        Dict with:
            - cost_per_interval: Cost per interval in USD
            - hourly_cost: Total hourly cost for all nodes
            - instance_type: AWS instance type selected
            - provider: Cloud provider (AWS)
    """
    inst = find_minimum_viable_instance(node_cpu, node_memory)
    
    if not inst:
        return {
            "cost_per_interval": 0.0,
            "hourly_cost": 0.0,
            "instance_type": None,
            "provider": None
        }
    
    hourly_price = float(inst["price_usd_per_hour"])
    hourly_total = hourly_price * max(1, node_quantity)
    interval_cost = (hourly_total * interval_seconds) / 3600.0
    
    return {
        "cost_per_interval": round(interval_cost, 10),
        "hourly_cost": round(hourly_total, 6),
        "instance_type": inst["name"],
        "provider": inst["provider"]
    }

