import os
import datetime
import pandas as pd
import warnings
from plotnine.exceptions import PlotnineWarning
from plotnine import (
    ggplot, aes, geom_step, geom_point, labs, geom_vline, facet_wrap, 
    scale_color_manual, scale_linetype_manual, scale_x_continuous,
    scale_y_continuous, theme_bw, theme, element_blank, expand_limits
)

warnings.filterwarnings("ignore", category=PlotnineWarning)
os.environ['LIBGL_DEBUG'] = 'quiet'

def plot_cpu_load(df, output_dir):
    """Plot CPU load by cluster over time using plotnine."""
    plot_df = df.melt(id_vars=['time_seconds'], value_vars=['cpu_load_private', 'cpu_load_public'],
                        var_name='Cluster', value_name='CPU Load')
    plot_df['Cluster'] = plot_df['Cluster'].map({'cpu_load_private': 'Private', 'cpu_load_public': 'Public'})

    max_time = df['time_seconds'].max()    
    x_breaks = list(range(0, int(max_time) + 120, 120))
    if len(x_breaks) > 20:
        x_breaks = list(range(0, int(max_time) + 300, 300))
    elif len(x_breaks) < 4:
        x_breaks = list(range(0, int(max_time) + 15, 15))


    g = (
        ggplot(plot_df, aes(x='time_seconds', y='CPU Load', color='Cluster'))
        + geom_step(size=1.5)
        + labs(title="CPU Load by Cluster over time", y="CPU Load", x="Time (seconds)")
        + scale_x_continuous(breaks=x_breaks)
        + scale_y_continuous(limits=(0, None))  # Force Y-axis to start from 0
        + theme_bw()
        + theme(legend_key=element_blank()) 
    )

    timestamp = datetime.datetime.now().strftime('%Y-%m-%d-%H-%M-%S')
    filename_with_timestamp = os.path.splitext("cpu_load.png")[0] + '_' + timestamp + os.path.splitext("cpu_load.png")[1]
    output_path = os.path.join(output_dir, filename_with_timestamp)
    g.save(output_path, width=12, height=6, dpi=300)

def plot_memory_load(df, output_dir):
    """Plot memory load by cluster over time using plotnine."""
    plot_df = df.melt(id_vars=['time_seconds'], value_vars=['mem_load_private', 'mem_load_public'],
                        var_name='Cluster', value_name='Memory Load')
    plot_df['Cluster'] = plot_df['Cluster'].map({'mem_load_private': 'Private', 'mem_load_public': 'Public'})

    max_time = df['time_seconds'].max()
    x_breaks = list(range(0, int(max_time) + 120, 120))
    if len(x_breaks) > 20:
        x_breaks = list(range(0, int(max_time) + 300, 300))
    elif len(x_breaks) < 4:
        x_breaks = list(range(0, int(max_time) + 15, 15))


    g = (
        ggplot(plot_df, aes(x='time_seconds', y='Memory Load', color='Cluster'))
        + geom_step(size=1.5)
        + labs(title="Memory Load by Cluster over time", y="Memory Load", x="Time (seconds)")
        + scale_x_continuous(breaks=x_breaks)
        + scale_y_continuous(limits=(0, None))  # Force Y-axis to start from 0
        + theme_bw()
        + theme(legend_key=element_blank()) 
    )

    timestamp = datetime.datetime.now().strftime('%Y-%m-%d-%H-%M-%S')
    filename_with_timestamp = os.path.splitext("memory_load.png")[0] + '_' + timestamp + os.path.splitext("memory_load.png")[1]
    output_path = os.path.join(output_dir, filename_with_timestamp)
    g.save(output_path, width=12, height=6, dpi=300)

def plot_total_percent_pending(df, output_dir):
    """Plot total percent pending pods over time."""
    max_time = df['time_seconds'].max() if not df.empty else 0
    x_breaks = list(range(0, int(max_time) + 120, 120))
    if len(x_breaks) > 20:
        x_breaks = list(range(0, int(max_time) + 300, 300))
    elif len(x_breaks) < 4:
        x_breaks = list(range(0, int(max_time) + 15, 15))

    # Create a copy of the dataframe to avoid modifying the original
    plot_df = df.copy()
    plot_df['total_percent_pending'] = plot_df['total_percent_pending'] * 100

    g = (
        ggplot(plot_df, aes(x='time_seconds', y='total_percent_pending'))
        + geom_step(color='black', size=1)
        + labs(title="Total Percent Pending over time", y="Percent Pending (%)", x="Time (seconds)")
        + scale_x_continuous(breaks=x_breaks)
        + scale_y_continuous(limits=(0, None))  # Force Y-axis to start from 0
        + theme_bw()
        + theme(legend_key=element_blank()) 
    )

    timestamp = datetime.datetime.now().strftime('%Y-%m-%d-%H-%M-%S')
    filename_with_timestamp = os.path.splitext("total_percent_pending.png")[0] + '_' + timestamp + os.path.splitext("total_percent_pending.png")[1]
    output_path = os.path.join(output_dir, filename_with_timestamp)
    g.save(output_path, width=12, height=6, dpi=300)

def plot_resource(df, value_vars, cap_vars, pending_vars, title, filename, migration_data=None):
    """
    Generates a 4-panel plot for resource usage and pending pods.

    Layout:
    1. Top: Private Cluster - Pending Pods
    2. Mid-Top: Private Cluster - Resource Usage
    3. Mid-Bottom: Public Cluster - Resource Usage
    4. Bottom: Public Cluster - Pending Pods
    """
    df = df.copy()

    # Ensure a time_seconds column exists, starting from 0
    if 'timestamp' in df.columns:
        start_time = df['timestamp'].min() # This is the starting point (time zero)
        df['time_seconds'] = (df['timestamp'] - start_time).dt.total_seconds()
    else:
        df['time_seconds'] = df.index * 60  # Fallback
        start_time = None # No start_time defined

    min_time = df['time_seconds'].min()
    df['time_seconds'] = df['time_seconds'] - min_time

    # --- 1. Prepare Resource data (Usage and Capacity) ---
    df_usage_melt = df.melt(id_vars=['time_seconds'], value_vars=value_vars, var_name='metric', value_name='value')
    df_usage_melt['cluster'] = df_usage_melt['metric'].apply(lambda x: 'Public' if 'public' in x else 'Private')
    df_usage_melt['type'] = 'Load'

    df_cap_melt = df.melt(id_vars=['time_seconds'], value_vars=cap_vars, var_name='metric', value_name='value')
    df_cap_melt['cluster'] = df_cap_melt['metric'].apply(lambda x: 'Public' if 'public' in x else 'Private')
    df_cap_melt['type'] = 'Capacity'

    plot_df_resources = pd.concat([df_usage_melt, df_cap_melt], ignore_index=True)
    plot_df_resources['plot_group'] = plot_df_resources['cluster'].apply(lambda x: f'{x} Cluster Resources')

    # --- 2. Prepare Pending Pods data ---
    df_pending_melt = df.melt(id_vars=['time_seconds'], value_vars=pending_vars, var_name='metric', value_name='value')
    df_pending_melt['cluster'] = df_pending_melt['metric'].apply(lambda x: 'Public' if 'public' in x else 'Private')
    df_pending_melt['type'] = 'Pending'
    df_pending_melt['plot_group'] = df_pending_melt['cluster'].apply(lambda x: f'{x} Cluster Pending Pods')

    pending_groups = [
        'Private Cluster Pending Pods',
        'Public Cluster Pending Pods'
    ]
    ref_points_data = []
    for group in pending_groups:
        ref_points_data.append({'plot_group': group, 'time_seconds': df['time_seconds'].min(), 'value': 0})
        ref_points_data.append({'plot_group': group, 'time_seconds': df['time_seconds'].min(), 'value': 1})
    
    ref_df = pd.DataFrame(ref_points_data)

    # --- 3. Combine DataFrames and set the plot order ---
    plot_df = pd.concat([plot_df_resources, df_pending_melt], ignore_index=True)

    plot_order = [
        'Private Cluster Pending Pods',
        'Private Cluster Resources',
        'Public Cluster Resources',
        'Public Cluster Pending Pods'
    ]
    plot_df['plot_group'] = pd.Categorical(plot_df['plot_group'], categories=plot_order, ordered=True)

    categories = [
        'Load', 'Capacity', 'Pending', 'Migration to Private',
        'Migration to Public', 'Both Migrations', 'No Migration'
    ]
    plot_df['type'] = pd.Categorical(plot_df['type'],
                                   categories=categories,
                                   ordered=True)
    plot_df = plot_df.sort_values('type')

    # Color and linetype maps
    color_map = {
        'Load': '#d62728', 'Capacity': '#1f77b4', 'Pending': '#8c564b',
        'Migration to Private': '#9467bd', 'Migration to Public': '#ff7f0e', 'Both Migrations': '#2ca02c', 'No Migration': '#5f615f',
    }
    linetype_map = {
        'Load': 'solid', 'Capacity': 'dashed', 'Pending': 'solid',
        'Migration to Private': 'dotted', 'Migration to Public': 'dotted', 'Both Migrations': 'dotted', 'No Migration': 'dotted'
    }

    # Calculate X-axis intervals
    max_time = df['time_seconds'].max()
    x_breaks = list(range(0, int(max_time) + 120, 120))
    if len(x_breaks) > 20:
        x_breaks = list(range(0, int(max_time) + 300, 300))
    elif len(x_breaks) < 4:
        x_breaks = list(range(0, int(max_time) + 15, 15))

    # --- 4. Create the plot with ggplot ---
    g = (
        ggplot(plot_df)
        + geom_step(
            aes(x='time_seconds', y='value', color='type', linetype='type'),
            size=1.5,
            na_rm=True
        )
        + geom_point(data=ref_df, mapping=aes(x='time_seconds', y='value'), alpha=0)
        + facet_wrap(
            '~plot_group',
            ncol=1,
            scales='free_y',
            labeller=lambda x: x.replace(" Resources", "").replace(
                " Pending Pods", "\n(Pending Pods)"
            )
        )
        + labs(title=title, y='Value', x='Time (seconds)', color='Legend', linetype='Legend')
        + scale_x_continuous(breaks=x_breaks, limits=(0, max_time))
        + scale_y_continuous(limits=(0, None))  # Force Y-axis to start from 0 and no negative values
        + theme_bw()
        + theme(legend_key=element_blank()) 
    )

    # Add vertical lines for migrations (will be applied to all panels)
    if migration_data is not None and not migration_data.empty and 'timestamp' in df.columns:
        start_time = df['timestamp'].min()
        end_time = df['timestamp'].max()
        max_time = (end_time - start_time).total_seconds()

        migration_data = migration_data.copy()
        migration_data['timestamp_dt'] = pd.to_datetime(migration_data['timestamp'], unit='s')
        
        # Subtract 3 hours from migration timestamps to align with metrics
        migration_data['timestamp_dt'] = migration_data['timestamp_dt'] - pd.Timedelta(hours=3)
        
        migration_data['xintercept'] = (migration_data['timestamp_dt'] - start_time).dt.total_seconds()

        # Mapping for the legend
        migration_map = {
            'private': 'Migration to Private',
            'public': 'Migration to Public',
            'both': 'Both Migrations',
            'no migration': 'No Migration'
        }
        migration_data['mig_legend'] = migration_data['type'].map(migration_map)

        # Filter only valid values within the plot range
        migration_data_filtered = migration_data[
            (migration_data['xintercept'] >= 0) &
            (migration_data['xintercept'] <= max_time)
        ]

        if not migration_data_filtered.empty:
            # Use color and legend mapping again
            g += geom_vline(
                data=migration_data_filtered,
                mapping=aes(
                    xintercept='xintercept',
                    color='mig_legend',
                    linetype='mig_legend'
                ),
                size=1.5,
                show_legend=False
            )

    g += scale_color_manual(name='Legend', values=color_map)
    g += scale_linetype_manual(name='Legend', values=linetype_map)

    # Ensure the output directory exists
    os.makedirs(os.path.dirname(filename) or '.', exist_ok=True)
    # Increase height to accommodate the 4 plots
    timestamp = datetime.datetime.now().strftime('%Y-%m-%d-%H-%M-%S')
    filename_with_timestamp = os.path.splitext(filename)[0] + '_' + timestamp + os.path.splitext(filename)[1]
    g.save(filename_with_timestamp, width=16, height=12, dpi=300)

def plot_pricing(df, output_dir, migration_data=None, instance_types=None):
    """
    Plot pricing data for both clusters showing cost per interval and cumulative costs.
    Creates a 4-panel layout: cost per interval (2 panels) and cumulative costs (2 panels).
    
    Args:
        df: DataFrame containing pricing data with columns:
            'time_seconds', 'cost_public', 'cost_private', 'cost_total',
            'cumulative_cost_public', 'cumulative_cost_private', 'cumulative_cost_total'
        output_dir: Directory to save the plot
        migration_data: DataFrame containing migration events (optional)
        instance_types: Dict with 'public' and 'private' instance type names (optional)
    """
    # Calculate X-axis intervals
    max_time = df['time_seconds'].max() if not df.empty else 0
    x_breaks = list(range(0, int(max_time) + 120, 120))
    if len(x_breaks) > 20:
        x_breaks = list(range(0, int(max_time) + 300, 300))
    elif len(x_breaks) < 4:
        x_breaks = list(range(0, int(max_time) + 15, 15))

    # Prepare data for cost per interval plot
    plot_df_interval = df.melt(id_vars=['time_seconds'], 
                               value_vars=['cost_public', 'cost_private'],
                               var_name='cluster', value_name='cost')
    plot_df_interval['cluster'] = plot_df_interval['cluster'].map({
        'cost_public': 'Public', 'cost_private': 'Private'
    })
    plot_df_interval['type'] = 'Cost per Interval'
    plot_df_interval['plot_group'] = plot_df_interval['cluster'].apply(
        lambda x: f'{x} Cluster - Cost per Interval'
    )

    # Prepare data for cumulative cost plot
    plot_df_cumulative = df.melt(id_vars=['time_seconds'],
                                value_vars=['cumulative_cost_public', 'cumulative_cost_private'],
                                var_name='cluster', value_name='cost')
    plot_df_cumulative['cluster'] = plot_df_cumulative['cluster'].map({
        'cumulative_cost_public': 'Public', 'cumulative_cost_private': 'Private'
    })
    plot_df_cumulative['type'] = 'Cumulative Cost'
    plot_df_cumulative['plot_group'] = plot_df_cumulative['cluster'].apply(
        lambda x: f'{x} Cluster - Cumulative Cost'
    )

    # Combine dataframes
    plot_df = pd.concat([plot_df_interval, plot_df_cumulative], ignore_index=True)
    
    # Set plot order
    plot_order = [
        'Private Cluster - Cost per Interval',
        'Public Cluster - Cost per Interval',
        'Private Cluster - Cumulative Cost',
        'Public Cluster - Cumulative Cost'
    ]
    plot_df['plot_group'] = pd.Categorical(plot_df['plot_group'], 
                                          categories=plot_order, ordered=True)

    # Color mapping
    color_map = {
        'Public': '#d62728',  # Red
        'Private': '#1f77b4',  # Blue
        'Migration to Private': '#9467bd',
        'Migration to Public': '#ff7f0e',
        'Both Migrations': '#2ca02c',
        'No Migration': '#5f615f'
    }
    
    # Build title with instance types
    title = "Cluster Pricing Analysis"
    if instance_types:
        instance_parts = []
        if 'private' in instance_types:
            instance_parts.append(f"Private: {instance_types['private']}")
        if 'public' in instance_types:
            instance_parts.append(f"Public: {instance_types['public']}")
        if instance_parts:
            title += f" ({', '.join(instance_parts)})"

    # Create the base plot
    g = (
        ggplot(plot_df, aes(x='time_seconds', y='cost', color='cluster'))
        + geom_step(size=1.5)
        + facet_wrap('~plot_group', ncol=1, scales='free_y')
        + labs(title=title, y="Cost (USD)", x="Time (seconds)")
        + scale_x_continuous(breaks=x_breaks, limits=(0, max_time))
        + scale_color_manual(name='Cluster', values=color_map)
        + scale_y_continuous(limits=(0, None))
        + theme_bw()
        + theme(legend_key=element_blank())
    )

    # Add migration events overlay if available
    if migration_data is not None and not migration_data.empty and 'timestamp' in df.columns:
        start_time = df['timestamp'].min()
        end_time = df['timestamp'].max()
        
        migration_data = migration_data.copy()
        migration_data['timestamp_dt'] = pd.to_datetime(migration_data['timestamp'], unit='s')
        
        # Subtract 3 hours from migration timestamps to align with metrics
        migration_data['timestamp_dt'] = migration_data['timestamp_dt'] - pd.Timedelta(hours=3)
        
        migration_data['xintercept'] = (migration_data['timestamp_dt'] - start_time).dt.total_seconds()

        # Color mapping for migration types
        migration_map = {
            'private': 'Migration to Private',
            'public': 'Migration to Public',
            'both': 'Both Migrations',
            'no migration': 'No Migration'
        }
        migration_data['mig_legend'] = migration_data['type'].map(migration_map)

        # Filter only valid values within the plot range
        migration_data_filtered = migration_data[
            (migration_data['xintercept'] >= 0) &
            (migration_data['xintercept'] <= max_time)
        ]

        if not migration_data_filtered.empty:
            migration_linetype_map = {
                'Migration to Private': 'dotted',
                'Migration to Public': 'dotted',
                'Both Migrations': 'dotted',
                'No Migration': 'dotted'
            }
            
            g += geom_vline(
                data=migration_data_filtered,
                mapping=aes(
                    xintercept='xintercept',
                    color='mig_legend',
                    linetype='mig_legend'
                ),
                size=1.5,
                show_legend=False
            )
            
            g += scale_linetype_manual(name='Migration Events', values=migration_linetype_map)

    # Save the plot
    timestamp = datetime.datetime.now().strftime('%Y-%m-%d-%H-%M-%S')
    filename_with_timestamp = f"pricing_{timestamp}.png"
    output_path = os.path.join(output_dir, filename_with_timestamp)
    g.save(output_path, width=12, height=14, dpi=300)  # Increased height for 4 panels
