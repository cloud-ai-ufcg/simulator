import json
import pandas as pd
from plotnine import *
from collections import defaultdict
import re
from datetime import datetime


def parse_resource_value(value, unit):
    """Converte string de recurso para inteiro, removendo unidade."""
    return int(value.replace(unit, '')) if isinstance(value, str) else int(value)


def parse_migration_logs(log_filepath):
    """Extrai timestamps e tipos de migração do log."""
    migrations = []
    with open(log_filepath, 'r') as f:
        for line in f:
            match = re.search(r'(\d{4}/\d{2}/\d{2} \d{2}:\d{2}:\d{2}).*Label type: (.*)', line)
            if match:
                timestamp_str = match.group(1)
                label_type = match.group(2).strip()
                dt_object = pd.to_datetime(timestamp_str, format='%Y/%m/%d %H:%M:%S')
                migrations.append({'timestamp': dt_object, 'type': label_type})
    return pd.DataFrame(migrations) if migrations else pd.DataFrame(columns=['timestamp', 'type'])


def load_data(filepath):
    """Carrega dados JSON do arquivo."""
    with open(filepath) as f:
        return json.load(f)


def process_resources(data):
    """Processa alocação e uso de recursos a partir dos dados."""
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
    """Processa info de cluster (limitando ou não o load)."""
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
    """Monta DataFrame pandas dos dados processados."""
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
    """Melt do DataFrame para plotar com cluster/capacity."""
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


def plot_resource(df, value_vars, cluster_vars, cap_vars, y_label, title, filename, migration_data=None):
    """Função genérica para plotar uso/capacidade de recursos."""
    _, cluster_df, cap_df = melt_df_with_cluster_and_cap(
        df, value_vars, cluster_vars, cap_vars, 'type', y_label, f'{y_label}_cluster', f'{y_label}_cap')
    cluster_df = cluster_df.rename(columns={f'{y_label}_cluster': 'value'})
    cap_df = cap_df.rename(columns={f'{y_label}_cap': 'value'})
    cluster_df['type'] = 'Load'
    cap_df['type'] = 'Capacity'
    plot_df = pd.concat([cluster_df, cap_df], ignore_index=True)
    color_map = {
        'Load': '#d62728', 'Capacity': '#1f77b4',
        'Migração Private': '#9467bd', 'Migração Public': '#ff7f0e', 'Migração Both': '#2ca02c',
    }
    linetype_map = {'Load': 'solid', 'Capacity': 'dashed', 'Migração Private': 'dotted', 'Migração Public': 'dotted', 'Migração Both': 'dotted'}
    x_breaks = pd.date_range(df['timestamp'].min(), df['timestamp'].max(), periods=10)
    g = (
        ggplot(plot_df)
        + geom_step(aes('timestamp', 'value', color='type', linetype='type'), size=1.5)
        + facet_wrap('~cluster', nrow=2, labeller=lambda x: 'Public Cluster' if x == 'Public' else 'Private Cluster')
        + scale_linetype_manual(values={'Load': 'solid', 'Capacity': 'dashed'})
        + scale_color_manual(name='Legenda', values={'Load': '#d62728', 'Capacity': '#1f77b4'})
        + labs(title=title, y=y_label, x='Time', color='Legenda', linetype='Tipo')
        + scale_x_datetime(date_labels="%H:%M:%S", breaks=x_breaks)
        + theme_bw()
    )
    if migration_data is not None and not migration_data.empty:
        migration_data = migration_data.copy()
        migration_data['mig_legend'] = migration_data['type'].map({
            'private': 'Migração Private', 'public': 'Migração Public', 'both': 'Migração Both'
        })
        for mig_legend in ['Migração Private', 'Migração Public', 'Migração Both']:
            mig_df = migration_data[migration_data['mig_legend'] == mig_legend]
            if not mig_df.empty:
                g += geom_vline(data=mig_df, mapping=aes(xintercept='timestamp', color='mig_legend', linetype='mig_legend'), size=1)
        g += scale_color_manual(name='Legenda', values=color_map)
        g += scale_linetype_manual(values=linetype_map)
    g.save(filename, width=10, height=7, dpi=150)


def main():
    data = load_data('avaliator/data.json')
    migration_data = parse_migration_logs('simulator/data/output/logs/actuator.log')
    timestamps, mem_allocated, mem_unallocated, cpu_allocated, cpu_unallocated = process_resources(data)
    cluster_info_alloc = process_cluster_info(data, timestamps, limit_load=True)
    df_alloc = build_dataframe(timestamps, mem_allocated, mem_unallocated, cpu_allocated, cpu_unallocated, cluster_info_alloc)
    cluster_info_req = process_cluster_info(data, timestamps, limit_load=False)
    df_req = build_dataframe(timestamps, mem_allocated, mem_unallocated, cpu_allocated, cpu_unallocated, cluster_info_req)
    plot_resource(
        df_alloc,
        ['mem_allocated_public', 'mem_allocated_private'],
        ['cluster_mem_load_public', 'cluster_mem_load_private'],
        ['cluster_memory_capacity_public', 'cluster_memory_capacity_private'],
        'memory', 'Memory Allocated', 'avaliator/memoria_alocada.png',
        migration_data
    )
    plot_resource(
        df_req,
        ['mem_allocated_public', 'mem_allocated_private'],
        ['cluster_mem_load_public', 'cluster_mem_load_private'],
        ['cluster_memory_capacity_public', 'cluster_memory_capacity_private'],
        'memory', 'Memory Requested', 'avaliator/memoria_requested.png',
        migration_data
    )
    plot_resource(
        df_alloc,
        ['cpu_allocated_public', 'cpu_allocated_private'],
        ['cluster_cpu_load_public', 'cluster_cpu_load_private'],
        ['cluster_cpu_capacity_public', 'cluster_cpu_capacity_private'],
        'cpu', 'CPU Allocated', 'avaliator/cpu_alocada.png',
        migration_data
    )
    plot_resource(
        df_req,
        ['cpu_allocated_public', 'cpu_allocated_private'],
        ['cluster_cpu_load_public', 'cluster_cpu_load_private'],
        ['cluster_cpu_capacity_public', 'cluster_cpu_capacity_private'],
        'cpu', 'CPU Requested', 'avaliator/cpu_requested.png',
        migration_data
    )

if __name__ == "__main__":
    main()
