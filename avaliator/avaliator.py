import sys
import pandas as pd
import matplotlib.pyplot as plt
import seaborn as sns
from datetime import datetime
import json
import os
from plotnine import ggplot, aes, geom_step, labs, theme_bw, ggsave, scale_x_continuous, geom_area, scale_fill_manual, scale_color_manual, geom_ribbon
os.environ['LIBGL_DEBUG'] = 'quiet'

def load_data(json_path):
    """Load and parse JSON data into a DataFrame."""
    with open(json_path, 'r') as f:
        raw_data = json.load(f)
    
    records = []
    # Sort by timestamp to ensure correct order
    sorted_ts = sorted(raw_data.keys(), key=int)

    for ts_str in sorted_ts:
        ts = int(ts_str)
        data = raw_data[ts_str]
        records.append({
            "timestamp": datetime.fromtimestamp(ts),
            "cpu_load_private": data["cluster_load_cpu"]["private"],
            "cpu_load_public": data["cluster_load_cpu"]["public"],
            "mem_load_private": data["cluster_load_memory"]["private"],
            "mem_load_public": data["cluster_load_memory"]["public"],
            "number_of_pods_pending": data["number_of_pods_pending"],
            "number_pending_private": data["number_pending_private"],
            "number_pending_public": data["number_pending_public"],
            "total_percent_pending": data["total_percent_pending"],
            "percent_pending_private": data.get("percent_pending_private", 0),
            "percent_pending_public": data.get("percent_pending_public", 0)
        })
    
    df = pd.DataFrame(records)

    # Calculate elapsed time in seconds from the first timestamp
    if not df.empty:
        start_time = df['timestamp'].min()
        df['time_seconds'] = (df['timestamp'] - start_time).dt.total_seconds()
    else:
        df['time_seconds'] = pd.Series(dtype='float64')

    return df

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
    # print(f"CPU load plot saved to: {output_path}")

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
    # print(f"Memory load plot saved to: {output_path}")

def plot_pending_pods(df, output_dir):
    """Plot stacked step area for pending pods (private/public) over time using plotnine."""
    # Ensure data is sorted by time and prepare pod columns
    df = df.sort_values('time_seconds').reset_index(drop=True)
    df['private_pods'] = df['number_pending_private'].fillna(0)
    df['public_pods'] = df['number_pending_public'].fillna(0)
    df['total_pods'] = df['private_pods'] + df['public_pods']

    # Create a stepped version of the DataFrame for accurate area plotting
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
        # Stacked areas using the pre-stepped data
        + geom_area(aes(y='total_pods', fill="'Public'"), position='identity', alpha=0.7)
        + geom_area(aes(y='private_pods', fill="'Private'"), position='identity', alpha=0.7)
        # Line for the total
        + geom_step(aes(y='total_pods'), color='black', size=1)

        + labs(title="Total Pending Pods over time (Stacked Private/Public)", y="Pending Pods", x="Time (seconds)")
        + scale_x_continuous(breaks=x_breaks)
        + scale_fill_manual(name='Cluster', values={'Private': '#6495ED', 'Public': '#FFA500'})
        + theme_bw()
    )

    output_path = os.path.join(output_dir, "pending_pods.png")
    ggsave(g, filename=output_path, dpi=300, width=12, height=6)
    # print(f"Pending pods plot saved to: {output_path}")

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
    # print(f"Total percent pending plot saved to: {output_path}")

def main():
    """Main function to run the analysis."""
    sns.set_theme(style="whitegrid")

    if len(sys.argv) != 2:
        print("Usage: python avaliator.py <input_json_file>")
        sys.exit(1)
    
    json_path = sys.argv[1]
    
    # Create output directory for plots
    output_dir = os.path.join("../data", "output", "plots")
    if not os.path.exists(output_dir):
        os.makedirs(output_dir)
        # print(f"Created output directory: {output_dir}")
    
    try:
        df = load_data(json_path)
        plot_cpu_load(df, output_dir)
        plot_memory_load(df, output_dir)
        plot_pending_pods(df, output_dir)
        plot_total_percent_pending(df, output_dir)
        # print(f"\nAll plots have been saved to the '{output_dir}' directory.")
    except FileNotFoundError:
        print(f"Error: File '{json_path}' not found.")
        sys.exit(1)
    except json.JSONDecodeError as e:
        print(f"Error: Invalid JSON format in '{json_path}': {e}")
        sys.exit(1)
    except Exception as e:
        print(f"Error: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
