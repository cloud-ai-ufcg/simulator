import os
import pandas as pd
from plotnine import ggplot, aes, geom_step, labs, theme_bw, ggsave, scale_x_continuous, geom_area, scale_fill_manual, facet_wrap, geom_vline, scale_color_manual, scale_linetype_manual
import warnings
from plotnine.exceptions import PlotnineWarning
from data_processor import melt_df_with_cluster_and_cap

warnings.filterwarnings("ignore", category=PlotnineWarning)
os.environ['LIBGL_DEBUG'] = 'quiet'

def plot_cpu_load(df, output_dir):
    """Plot CPU load by cluster over time using plotnine."""
    plot_df = df.melt(id_vars=['time_seconds'], value_vars=['cpu_load_private', 'cpu_load_public'],
                        var_name='Cluster', value_name='CPU Load')
    plot_df['Cluster'] = plot_df['Cluster'].map({'cpu_load_private': 'Private', 'cpu_load_public': 'Public'})

    max_time = df['time_seconds'].max()
    x_breaks = range(0, int(max_time) + 120, 120)

    g = (
        ggplot(plot_df, aes(x='time_seconds', y='CPU Load', color='Cluster'))
        + geom_step(size=1.5)
        + labs(title="CPU Load by Cluster over time", y="CPU Load", x="Time (seconds)")
        + scale_x_continuous(breaks=x_breaks)
        + theme_bw()
    )
    
    output_path = os.path.join(output_dir, "cpu_load.png")
    ggsave(g, filename=output_path, dpi=300, width=12, height=6)

def plot_memory_load(df, output_dir):
    """Plot memory load by cluster over time using plotnine."""
    plot_df = df.melt(id_vars=['time_seconds'], value_vars=['mem_load_private', 'mem_load_public'],
                        var_name='Cluster', value_name='Memory Load')
    plot_df['Cluster'] = plot_df['Cluster'].map({'mem_load_private': 'Private', 'mem_load_public': 'Public'})

    max_time = df['time_seconds'].max()
    x_breaks = range(0, int(max_time) + 120, 120)

    g = (
        ggplot(plot_df, aes(x='time_seconds', y='Memory Load', color='Cluster'))
        + geom_step(size=1.5)
        + labs(title="Memory Load by Cluster over time", y="Memory Load", x="Time (seconds)")
        + scale_x_continuous(breaks=x_breaks)
        + theme_bw()
    )
    
    output_path = os.path.join(output_dir, "memory_load.png")
    ggsave(g, filename=output_path, dpi=300, width=12, height=6)

def plot_pending_pods(df, output_dir):
    """Plot stacked step area for pending pods (private/public) over time using plotnine."""
    df = df.sort_values('time_seconds').reset_index(drop=True)
    df['private_pods'] = df['number_pending_private'].fillna(0)
    df['public_pods'] = df['number_pending_public'].fillna(0)
    df['total_pods'] = df['private_pods'] + df['public_pods']

    if len(df) > 1:
        stepped_df = pd.concat([df.iloc[[0]]] + [
            row for i in range(len(df) - 1)
            for row in [df.iloc[[i]].assign(time_seconds=df.iloc[i+1].time_seconds), df.iloc[[i+1]]]
                ], ignore_index=True)
    else:
        stepped_df = df

    max_time = df['time_seconds'].max() if not df.empty else 0
    x_breaks = range(0, int(max_time) + 120, 120)

    g = (
        ggplot(stepped_df, aes(x='time_seconds'))
        + geom_area(aes(y='total_pods', fill="'Public'"), position='identity', alpha=0.7)
        + geom_area(aes(y='private_pods', fill="'Private'"), position='identity', alpha=0.7)
        + geom_step(aes(y='total_pods'), color='black', size=1)
        + labs(title="Total Pending Pods over time (Stacked Private/Public)", y="Pending Pods", x="Time (seconds)")
        + scale_x_continuous(breaks=x_breaks)
        + scale_fill_manual(name='Cluster', values={'Private': '#6495ED', 'Public': '#FFA500'})
        + theme_bw()
    )

    output_path = os.path.join(output_dir, "pending_pods.png")
    ggsave(g, filename=output_path, dpi=300, width=12, height=6)

def plot_total_percent_pending(df, output_dir):
    """Plot total percent pending pods over time."""
    max_time = df['time_seconds'].max() if not df.empty else 0
    x_breaks = range(0, int(max_time) + 120, 120)

    g = (
        ggplot(df, aes(x='time_seconds', y='total_percent_pending'))
        + geom_step(color='black', size=1)
        + labs(title="Total Percent Pending over time", y="Percent Pending (%)", x="Time (seconds)")
        + scale_x_continuous(breaks=x_breaks)
        + theme_bw()
    )
    
    output_path = os.path.join(output_dir, "total_percent_pending.png")
    ggsave(g, filename=output_path, dpi=300, width=12, height=6)

def plot_resource(df, value_vars, cluster_vars, cap_vars, y_label, title, filename, migration_data=None):
    """Generic function to plot resource usage/capacity."""
    # Ensure we have a time_seconds column starting from 0
    if 'time_seconds' not in df.columns and 'timestamp' in df.columns:
        start_time = df['timestamp'].min()
        df['time_seconds'] = (df['timestamp'] - start_time).dt.total_seconds()
    
    # Calculate time in seconds if not already done
    if 'time_seconds' not in df.columns:
        df['time_seconds'] = df.index * 60  # Assuming 1 minute intervals if no timestamp
    
    # Ensure time starts from 0
    min_time = df['time_seconds'].min()
    df['time_seconds'] = df['time_seconds'] - min_time

    _, cluster_df, cap_df = melt_df_with_cluster_and_cap(
        df, value_vars, cluster_vars, cap_vars, 'type', y_label, f'{y_label}_cluster', f'{y_label}_cap', id_vars=['time_seconds'])
    cluster_df = cluster_df.rename(columns={f'{y_label}_cluster': 'value'})
    cap_df = cap_df.rename(columns={f'{y_label}_cap': 'value'})
    cluster_df['type'] = 'Load'
    cap_df['type'] = 'Capacity'
    plot_df = pd.concat([cluster_df, cap_df], ignore_index=True)
    plot_df['type'] = pd.Categorical(plot_df['type'], categories=['Load', 'Capacity', 'Migration to Private', 'Migration to Public', 'Both Migrations', 'No Migration'], ordered=True)
    plot_df = plot_df.sort_values('type')
    
    color_map = {
        'Load': '#d62728', 'Capacity': '#1f77b4',
        'Migration to Private': '#9467bd', 'Migration to Public': '#ff7f0e', 'Both Migrations': '#2ca02c', 'No Migration': '#5f615f',
    }
    linetype_map = {
        'Load': 'solid', 'Capacity': 'dashed',
        'Migration to Private': 'dotted', 'Migration to Public': 'dotted', 'Both Migrations': 'dotted', 'No Migration': 'dotted'
    }

    # Calculate x-axis breaks every 120 seconds
    max_time = df['time_seconds'].max()
    x_breaks = list(range(0, int(max_time) + 120, 120))
    
    # Ensure we don't have too many labels if the time range is large
    if len(x_breaks) > 20:
        x_breaks = list(range(0, int(max_time) + 120, 300))  # Switch to 5-minute intervals if too many points

    g = (
        ggplot(plot_df)
        + geom_step(aes(x='time_seconds', y='value', color='type', linetype='type'), size=1.5, na_rm=True)
        + facet_wrap('~cluster', nrow=2, labeller=lambda x: 'Public Cluster' if x == 'Public' else 'Private Cluster')
        + labs(title=title, y=y_label, x='Time (seconds)', color='Legend', linetype='Legend')
        + scale_x_continuous(breaks=x_breaks, limits=(0, max_time))
        + theme_bw()
    )

    if migration_data is not None and not migration_data.empty:
        migration_data = migration_data.copy()
        migration_data['mig_legend'] = migration_data['type'].map({
            'private': 'Migration to Private', 'public': 'Migration to Public', 'both': 'Both Migrations', 'no migration': 'No Migration'
        })
        # Adjust migration times to be relative to the start time
        migration_data['xintercept'] = migration_data['execution'] * 60 - min_time
        
        # Only include migrations that are within the plot's time range
        migration_data = migration_data[(migration_data['xintercept'] >= 0) & (migration_data['xintercept'] <= max_time)]
        
        if not migration_data.empty:
            g += geom_vline(
                migration_data,
                aes(xintercept='xintercept', color='mig_legend', linetype='mig_legend'),
                size=1.5,
                show_legend=False
            )

    g += scale_color_manual(name='Legend', values=color_map)
    g += scale_linetype_manual(name='Legend', values=linetype_map)
    
    # Ensure output directory exists
    os.makedirs(os.path.dirname(filename) or '.', exist_ok=True)
    g.save(filename, width=16, height=7, dpi=150)
