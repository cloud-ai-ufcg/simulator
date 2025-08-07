import pandas as pd
from plotnine import *
from utils import load_data
from migration import parse_migration_logs
from processing import process_resources, process_cluster_info, build_dataframe, melt_df_with_cluster_and_cap
import warnings
from plotnine.exceptions import PlotnineWarning

warnings.filterwarnings("ignore", category=PlotnineWarning)


def plot_resource(df, value_vars, cluster_vars, cap_vars, y_label, title, filename, migration_data=None):
    """Generic function to plot resource usage/capacity."""
    _, cluster_df, cap_df = melt_df_with_cluster_and_cap(
        df, value_vars, cluster_vars, cap_vars, 'type', y_label, f'{y_label}_cluster', f'{y_label}_cap')
    cluster_df = cluster_df.rename(columns={f'{y_label}_cluster': 'value'})
    cap_df = cap_df.rename(columns={f'{y_label}_cap': 'value'})
    cluster_df['type'] = 'Load'
    cap_df['type'] = 'Capacity'
    # Concatenar com Capacity depois de Load para Capacity ficar acima
    plot_df = pd.concat([cluster_df, cap_df], ignore_index=True)
    # Garantir que Capacity venha depois de Load na ordem dos dados
    plot_df['type'] = pd.Categorical(plot_df['type'], categories=['Load', 'Capacity', 'Private AI Migration', 'Public AI Migration', 'Both AI Migrations'], ordered=True)
    plot_df = plot_df.sort_values('type')
    
    color_map = {
        'Load': '#d62728', 'Capacity': '#1f77b4',
        'Private AI Migration': '#9467bd', 'Public AI Migration': '#ff7f0e', 'Both AI Migrations': '#2ca02c',
    }
    linetype_map = {
        'Load': 'solid', 'Capacity': 'dashed',
        'Private AI Migration': 'dotted', 'Public AI Migration': 'dotted', 'Both AI Migrations': 'dotted'
    }
    x_breaks = pd.date_range(df['timestamp'].min(), df['timestamp'].max(), periods=10)
    # Base plot
    g = (
        ggplot(plot_df)
        + geom_step(aes(x='timestamp', y='value', color='type', linetype='type'), size=1.5, na_rm=True)
        + facet_wrap('~cluster', nrow=2, labeller=lambda x: 'Public Cluster' if x == 'Public' else 'Private Cluster')
        + labs(title=title, y=y_label, x='Time (HH:MM:SS)', color='Legend', linetype='Legend')
        + scale_x_datetime(breaks=x_breaks, date_labels='%H:%M:%S')
        + theme_bw()
    )

    # Add migration lines if they exist
    if migration_data is not None and not migration_data.empty:
        migration_data = migration_data.copy()
        migration_data['mig_legend'] = migration_data['type'].map({
            'private': 'Private AI Migration', 'public': 'Public AI Migration', 'both': 'Both AI Migrations'
        })
        g += geom_vline(
            migration_data,
            aes(xintercept='timestamp', color='mig_legend', linetype='mig_legend'),
            size=1,
            show_legend=False
        )

    # Apply color and linetype scales
    g += scale_color_manual(name='Legend', values=color_map)
    g += scale_linetype_manual(name='Legend', values=linetype_map)
    
    g.save(filename, width=16, height=7, dpi=150)


def main():
    data = load_data('../../avaliator/data/metrics.json')
    migration_data = parse_migration_logs('../data/output/logs/actuator.log')
    timestamps, mem_allocated, mem_requested, cpu_allocated, cpu_requested = process_resources(data)
    cluster_info_alloc = process_cluster_info(data, timestamps, limit_load=True)
    df_alloc = build_dataframe(timestamps, mem_allocated, mem_requested, cpu_allocated, cpu_requested, cluster_info_alloc)
    cluster_info_req = process_cluster_info(data, timestamps, limit_load=False)
    df_req = build_dataframe(timestamps, mem_allocated, mem_requested, cpu_allocated, cpu_requested, cluster_info_req)
    plot_resource(
        df_alloc,
        ['mem_allocated_public', 'mem_allocated_private'],
        ['cluster_mem_load_public', 'cluster_mem_load_private'],
        ['cluster_memory_capacity_public', 'cluster_memory_capacity_private'],
        'Memory (in Gb)', 'Memory Allocated', '../data/output/plots/allocated_memory.png',
        migration_data
    )
    plot_resource(
        df_req,
        ['mem_requested_public', 'mem_requested_private'],
        ['cluster_mem_load_public', 'cluster_mem_load_private'],
        ['cluster_memory_capacity_public', 'cluster_memory_capacity_private'],
        'Memory (in Gb)', 'Memory Requested', '../data/output/plots/requested_memory.png',
        migration_data
    )
    plot_resource(
        df_alloc,
        ['cpu_allocated_public', 'cpu_allocated_private'],
        ['cluster_cpu_load_public', 'cluster_cpu_load_private'],
        ['cluster_cpu_capacity_public', 'cluster_cpu_capacity_private'],
        'CPU (in cores)', 'CPU Allocated', '../data/output/plots/allocated_cpu.png',
        migration_data
    )
    plot_resource(
        df_req,
        ['cpu_requested_public', 'cpu_requested_private'],
        ['cluster_cpu_load_public', 'cluster_cpu_load_private'],
        ['cluster_cpu_capacity_public', 'cluster_cpu_capacity_private'],
        'CPU (in cores)', 'CPU Requested', '../data/output/plots/requested_cpu.png',
        migration_data
    )

if __name__ == "__main__":
    main()
