import pandas as pd
from collections import defaultdict
from utils import parse_resource_value

def process_resources(data):
    """Processes resource allocation and usage from data."""
    timestamps = sorted([int(ts) for ts in data.keys()])
    mem_allocated, mem_unallocated = defaultdict(list), defaultdict(list)
    cpu_allocated, cpu_unallocated = defaultdict(list), defaultdict(list)
    for ts in timestamps:
        ts_str = str(ts)
        workloads = data[ts_str]['workloads']
        mem_used = {'public': 0, 'private': 0}
        cpu_used = {'public': 0, 'private': 0}
        mem_unalloc = {'public': 0, 'private': 0}
        cpu_unalloc = {'public': 0, 'private': 0}
        for w in workloads:
            label = w['cluster_label']
            pods_total = w.get('pods_total', 1)
            pods_pending = w.get('pods_pending', 0)
            mem = parse_resource_value(w['resources'].get('memory', '0'), 'Mi') * pods_total
            cpu = parse_resource_value(w['resources'].get('cpu', '0'), 'm') * pods_total
            if pods_total:
                mem_used[label] += mem * (pods_total - pods_pending) // pods_total
                cpu_used[label] += cpu * (pods_total - pods_pending) // pods_total
                mem_unalloc[label] += mem * pods_pending // pods_total
                cpu_unalloc[label] += cpu * pods_pending // pods_total
        for label in ['public', 'private']:
            mem_allocated[label].append(mem_used[label])
            mem_unallocated[label].append(mem_unalloc[label])
            cpu_allocated[label].append(cpu_used[label])
            cpu_unallocated[label].append(cpu_unalloc[label])
    return timestamps, mem_allocated, mem_unallocated, cpu_allocated, cpu_unallocated

def process_cluster_info(data, timestamps, limit_load=True):
    """Processes cluster info (limiting load or not)."""
    result = {k: [] for k in [
        'mem_load_public', 'mem_load_private', 'cpu_load_public', 'cpu_load_private',
        'cpu_capacity_public', 'cpu_capacity_private', 'memory_capacity_public', 'memory_capacity_private']}
    for ts in timestamps:
        ts_str = str(ts)
        for c in data[ts_str]['cluster_info']:
            mem_load = c['cluster_load'].get('memory', 0)
            cpu_load = c['cluster_load'].get('cpu', 0)
            if limit_load:
                mem_load = min(mem_load, 1.0)
                cpu_load = min(cpu_load, 1.0)
            mem_cap = parse_resource_value(c['cluster_memory_capacity'], 'Mi')
            cpu_cap = parse_resource_value(c['cluster_cpu_capacity'], 'm')
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
        result['memory_capacity_public'], result['memory_capacity_private']
    )

def build_dataframe(timestamps, mem_allocated, mem_unallocated, cpu_allocated, cpu_unallocated, cluster_info):
    """Builds a pandas DataFrame from the processed data."""
    index = pd.to_datetime(timestamps, unit='s')
    df = pd.DataFrame({
        'timestamp': index,
        'mem_allocated_public': mem_allocated['public'],
        'mem_allocated_private': mem_allocated['private'],
        'mem_unallocated_public': mem_unallocated['public'],
        'mem_unallocated_private': mem_unallocated['private'],
        'cpu_allocated_public': cpu_allocated['public'],
        'cpu_allocated_private': cpu_allocated['private'],
        'cpu_unallocated_public': cpu_unallocated['public'],
        'cpu_unallocated_private': cpu_unallocated['private'],
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

def melt_df_with_cluster_and_cap(df, value_vars, cluster_vars, cap_vars, var_name, value_name, cluster_value_name, cap_value_name):
    """Melts the DataFrame to plot with cluster/capacity."""
    melted = pd.melt(
        df, id_vars=['timestamp'], value_vars=value_vars, var_name=var_name, value_name=value_name
    )
    melted['cluster'] = melted[var_name].apply(lambda x: 'Public' if 'public' in x else 'Private')
    cluster_df = pd.melt(
        df, id_vars=['timestamp'], value_vars=cluster_vars, var_name=var_name, value_name=cluster_value_name
    )
    cluster_df['cluster'] = cluster_df[var_name].apply(lambda x: 'Public' if 'public' in x else 'Private')
    cluster_df['type'] = 'cluster_load'
    cap_df = pd.melt(
        df, id_vars=['timestamp'], value_vars=cap_vars, var_name=var_name, value_name=cap_value_name
    )
    cap_df['cluster'] = cap_df[var_name].apply(lambda x: 'Public' if 'public' in x else 'Private')
    cap_df['type'] = 'capacity'
    return melted, cluster_df, cap_df
