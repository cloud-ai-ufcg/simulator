import json
import pandas as pd
from plotnine import *
from collections import defaultdict
from plotnine import ggplot, aes, geom_line, facet_wrap, scale_linetype_manual, labs, theme_bw, scale_color_manual


def load_data(filepath):
    """Load JSON data from file."""
    with open(filepath) as f:
        return json.load(f)

def process_resources(data):
    """Process resource allocation and usage from data."""
    timestamps = sorted([int(ts) for ts in data.keys()])
    mem_allocated = defaultdict(list)
    mem_unallocated = defaultdict(list)
    cpu_allocated = defaultdict(list)
    cpu_unallocated = defaultdict(list)
    for ts in timestamps:
        ts_str = str(ts)
        workloads = data[ts_str]['workloads']
        clusters = {c['cluster_label']: c for c in data[ts_str]['cluster_info']}
        mem_used = {'public': 0, 'private': 0}
        cpu_used = {'public': 0, 'private': 0}
        mem_unalloc = {'public': 0, 'private': 0}
        cpu_unalloc = {'public': 0, 'private': 0}
        for w in workloads:
            label = w['cluster_label']
            pods_total = w.get('pods_total', 1)
            pods_pending = w.get('pods_pending', 0)
            mem = int(w['resources'].get('memory', '0').replace('Mi', '')) * pods_total
            cpu = int(w['resources'].get('cpu', '0').replace('m', '')) * pods_total
            mem_used[label] += mem * (pods_total - pods_pending) // pods_total if pods_total else 0
            cpu_used[label] += cpu * (pods_total - pods_pending) // pods_total if pods_total else 0
            mem_unalloc[label] += mem * pods_pending // pods_total if pods_total else 0
            cpu_unalloc[label] += cpu * pods_pending // pods_total if pods_total else 0
        for label in ['public', 'private']:
            mem_allocated[label].append(mem_used[label])
            mem_unallocated[label].append(mem_unalloc[label])
            cpu_allocated[label].append(cpu_used[label])
            cpu_unallocated[label].append(cpu_unalloc[label])
    return timestamps, mem_allocated, mem_unallocated, cpu_allocated, cpu_unallocated

def process_cluster_info_allocated(data, timestamps):
    """Process cluster load and capacity info for allocated (limit load to 1)."""
    cluster_mem_load_public = []
    cluster_mem_load_private = []
    cluster_cpu_load_public = []
    cluster_cpu_load_private = []
    cluster_cpu_capacity_public = []
    cluster_cpu_capacity_private = []
    cluster_memory_capacity_public = []
    cluster_memory_capacity_private = []
    for ts in timestamps:
        ts_str = str(ts)
        info = data[ts_str]['cluster_info']
        for c in info:
            mem_load_val = c['cluster_load'].get('memory', 0)
            cpu_load_val = c['cluster_load'].get('cpu', 0)
            mem_load = mem_load_val if mem_load_val <= 1.0 else 1.0
            cpu_load = cpu_load_val if cpu_load_val <= 1.0 else 1.0
            if c['cluster_label'] == 'public':
                cluster_mem_load_public.append(mem_load * int(c['cluster_memory_capacity'].replace('Mi','')))
                cluster_cpu_load_public.append(cpu_load * int(c['cluster_cpu_capacity'].replace('m','')))
                cluster_cpu_capacity_public.append(int(c['cluster_cpu_capacity'].replace('m','')))
                cluster_memory_capacity_public.append(int(c['cluster_memory_capacity'].replace('Mi','')))
            elif c['cluster_label'] == 'private':
                cluster_mem_load_private.append(mem_load * int(c['cluster_memory_capacity'].replace('Mi','')))
                cluster_cpu_load_private.append(cpu_load * int(c['cluster_cpu_capacity'].replace('m','')))
                cluster_cpu_capacity_private.append(int(c['cluster_cpu_capacity'].replace('m','')))
                cluster_memory_capacity_private.append(int(c['cluster_memory_capacity'].replace('Mi','')))
    return (cluster_mem_load_public, cluster_mem_load_private, cluster_cpu_load_public, cluster_cpu_load_private,
            cluster_cpu_capacity_public, cluster_cpu_capacity_private, cluster_memory_capacity_public, cluster_memory_capacity_private)

def process_cluster_info_estimated(data, timestamps):
    """Process cluster load and capacity info for estimated (do not limit load)."""
    cluster_mem_load_public = []
    cluster_mem_load_private = []
    cluster_cpu_load_public = []
    cluster_cpu_load_private = []
    cluster_cpu_capacity_public = []
    cluster_cpu_capacity_private = []
    cluster_memory_capacity_public = []
    cluster_memory_capacity_private = []
    for ts in timestamps:
        ts_str = str(ts)
        info = data[ts_str]['cluster_info']
        for c in info:
            mem_load = c['cluster_load'].get('memory', 0)
            cpu_load = c['cluster_load'].get('cpu', 0)
            if c['cluster_label'] == 'public':
                cluster_mem_load_public.append(mem_load * int(c['cluster_memory_capacity'].replace('Mi','')))
                cluster_cpu_load_public.append(cpu_load * int(c['cluster_cpu_capacity'].replace('m','')))
                cluster_cpu_capacity_public.append(int(c['cluster_cpu_capacity'].replace('m','')))
                cluster_memory_capacity_public.append(int(c['cluster_memory_capacity'].replace('Mi','')))
            elif c['cluster_label'] == 'private':
                cluster_mem_load_private.append(mem_load * int(c['cluster_memory_capacity'].replace('Mi','')))
                cluster_cpu_load_private.append(cpu_load * int(c['cluster_cpu_capacity'].replace('m','')))
                cluster_cpu_capacity_private.append(int(c['cluster_cpu_capacity'].replace('m','')))
                cluster_memory_capacity_private.append(int(c['cluster_memory_capacity'].replace('Mi','')))
    return (cluster_mem_load_public, cluster_mem_load_private, cluster_cpu_load_public, cluster_cpu_load_private,
            cluster_cpu_capacity_public, cluster_cpu_capacity_private, cluster_memory_capacity_public, cluster_memory_capacity_private)

def build_dataframe(timestamps, mem_allocated, mem_unallocated, cpu_allocated, cpu_unallocated, cluster_info):
    """Builds a pandas DataFrame from processed data."""
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
    """Melt DataFrame for plotting with cluster and capacity facets."""
    melted = pd.melt(
        df,
        id_vars=['timestamp'],
        value_vars=value_vars,
        var_name=var_name,
        value_name=value_name
    )
    melted['cluster'] = melted[var_name].apply(lambda x: 'Public' if 'public' in x else 'Private')
    cluster_df = pd.melt(
        df,
        id_vars=['timestamp'],
        value_vars=cluster_vars,
        var_name=var_name,
        value_name=cluster_value_name
    )
    cluster_df['cluster'] = cluster_df[var_name].apply(lambda x: 'Public' if 'public' in x else 'Private')
    cluster_df['type'] = 'cluster_load'
    cap_df = pd.melt(
        df,
        id_vars=['timestamp'],
        value_vars=cap_vars,
        var_name=var_name,
        value_name=cap_value_name
    )
    cap_df['cluster'] = cap_df[var_name].apply(lambda x: 'Public' if 'public' in x else 'Private')
    cap_df['type'] = 'capacity'
    return melted, cluster_df, cap_df

def plot_resource(df, value_vars, cluster_vars, cap_vars, y_label, title, filename):
    """Generic plot function for resource usage/capacity."""
    _, cluster_df, cap_df = melt_df_with_cluster_and_cap(
        df, value_vars, cluster_vars, cap_vars, 'type', y_label, f'{y_label}_cluster', f'{y_label}_cap')
    cluster_pub = cluster_df[cluster_df['cluster'] == 'Public'].assign(Legend='Cluster Load')
    cluster_priv = cluster_df[cluster_df['cluster'] == 'Private'].assign(Legend='Cluster Load')
    cap_pub = cap_df[cap_df['cluster'] == 'Public'].assign(Legend='Cluster Capacity')
    cap_priv = cap_df[cap_df['cluster'] == 'Private'].assign(Legend='Cluster Capacity')
    # Define more bins (breaks) for the x axis
    x_breaks = pd.date_range(df['timestamp'].min(), df['timestamp'].max(), periods=10)
    g = (
        ggplot()
        + geom_step(aes('timestamp', f'{y_label}_cluster', color='Legend', linetype='Legend'), size=1.5, data=cluster_pub)
        + geom_step(aes('timestamp', f'{y_label}_cap', color='Legend', linetype='Legend'), size=1.5, data=cap_pub)
        + geom_step(aes('timestamp', f'{y_label}_cluster', color='Legend', linetype='Legend'), size=1.5, data=cluster_priv)
        + geom_step(aes('timestamp', f'{y_label}_cap', color='Legend', linetype='Legend'), size=1.5, data=cap_priv)
        + facet_wrap('~cluster', nrow=2, labeller=lambda x: 'Public Cluster' if x == 'Public' else 'Private Cluster')
        + scale_linetype_manual(values=['solid', 'dashed'])
        + scale_color_manual(values={'Cluster Load': '#d62728', 'Cluster Capacity': '#1f77b4'})
        + labs(title=title, y=y_label, x='Time', linetype='Legend', color='Legend')
        + scale_x_datetime(date_labels="%H:%M:%S", breaks=x_breaks)
        + theme_bw()
    )
    g.save(filename, width=10, height=7, dpi=150)

def main():
    data = load_data('avaliator/data.json')
    timestamps, mem_allocated, mem_unallocated, cpu_allocated, cpu_unallocated = process_resources(data)
    # Alocado: limita o load a 1
    cluster_info_alloc = process_cluster_info_allocated(data, timestamps)
    df_alloc = build_dataframe(timestamps, mem_allocated, mem_unallocated, cpu_allocated, cpu_unallocated, cluster_info_alloc)
    # Estimado: não limita o load
    cluster_info_est = process_cluster_info_estimated(data, timestamps)
    df_est = build_dataframe(timestamps, mem_allocated, mem_unallocated, cpu_allocated, cpu_unallocated, cluster_info_est)
    plot_resource(
        df_alloc,
        ['mem_allocated_public', 'mem_allocated_private'],
        ['cluster_mem_load_public', 'cluster_mem_load_private'],
        ['cluster_memory_capacity_public', 'cluster_memory_capacity_private'],
        'memory', 'Memory Allocated', 'avaliator/memoria_alocada.png'
    )
    plot_resource(
        df_est,
        ['mem_allocated_public', 'mem_allocated_private'],
        ['cluster_mem_load_public', 'cluster_mem_load_private'],
        ['cluster_memory_capacity_public', 'cluster_memory_capacity_private'],
        'memory', 'Memory Estimated', 'avaliator/memoria_estimada.png'
    )
    plot_resource(
        df_alloc,
        ['cpu_allocated_public', 'cpu_allocated_private'],
        ['cluster_cpu_load_public', 'cluster_cpu_load_private'],
        ['cluster_cpu_capacity_public', 'cluster_cpu_capacity_private'],
        'cpu', 'CPU Allocated', 'avaliator/cpu_alocada.png'
    )
    plot_resource(
        df_est,
        ['cpu_allocated_public', 'cpu_allocated_private'],
        ['cluster_cpu_load_public', 'cluster_cpu_load_private'],
        ['cluster_cpu_capacity_public', 'cluster_cpu_capacity_private'],
        'cpu', 'CPU Estimated', 'avaliator/cpu_estimada.png'
    )

if __name__ == "__main__":
    main()
