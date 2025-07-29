import sys
import pandas as pd
import matplotlib.pyplot as plt
import seaborn as sns
from datetime import datetime
import json
import matplotlib.dates as mdates
import os
os.environ['LIBGL_DEBUG'] = 'quiet'

def load_data(json_path):
    """Load and parse JSON data into a DataFrame."""
    with open(json_path, 'r') as f:
        raw_data = json.load(f)
    
    records = []
    for ts, data in raw_data.items():
        records.append({
            "timestamp": datetime.fromtimestamp(int(ts)),
            "cpu_load_private": data["cluster_load_cpu"]["private"],
            "cpu_load_public": data["cluster_load_cpu"]["public"],
            "mem_load_private": data["cluster_load_memory"]["private"],
            "mem_load_public": data["cluster_load_memory"]["public"],
            "number_of_pods_pending": data["number_of_pods_pending"],
            "number_pending_private": data["number_pending_private"],
            "number_pending_public": data["number_pending_public"],
            "total_percent_pending": data["total_percent_pending"]
        })
    
    df = pd.DataFrame(records)
    df['time_str'] = df['timestamp'].dt.strftime('%H:%M')
    return df

def plot_cpu_load(df, output_dir):
    """Plot CPU load by cluster over time."""
    plt.figure(figsize=(12, 6))
    sns.lineplot(x="timestamp", y="cpu_load_private", data=df, label="CPU Load Private", marker="o")
    sns.lineplot(x="timestamp", y="cpu_load_public", data=df, label="CPU Load Public", marker="o")
    plt.title("CPU Load by Cluster over time")
    plt.ylabel("CPU Load")
    plt.xlabel("Time")
    ax = plt.gca()
    ax.xaxis.set_major_locator(mdates.AutoDateLocator())
    ax.xaxis.set_major_formatter(mdates.DateFormatter('%H:%M'))
    plt.xticks(rotation=45)
    plt.legend()
    plt.tight_layout()
    
    # Save the plot
    output_path = os.path.join(output_dir, "cpu_load.png")
    plt.savefig(output_path, dpi=300, bbox_inches='tight')
    # print(f"CPU load plot saved to: {output_path}")
    # plt.show()

def plot_memory_load(df, output_dir):
    """Plot memory load by cluster over time."""
    plt.figure(figsize=(12, 6))
    sns.lineplot(x="timestamp", y="mem_load_private", data=df, label="Mem Load Private", marker="o")
    sns.lineplot(x="timestamp", y="mem_load_public", data=df, label="Mem Load Public", marker="o")
    plt.title("Memory Load by Cluster over time")
    plt.ylabel("Memory Load")
    plt.xlabel("Time")
    ax = plt.gca()
    ax.xaxis.set_major_locator(mdates.AutoDateLocator())
    ax.xaxis.set_major_formatter(mdates.DateFormatter('%H:%M'))
    plt.xticks(rotation=45)
    plt.legend()
    plt.tight_layout()
    
    # Save the plot
    output_path = os.path.join(output_dir, "memory_load.png")
    plt.savefig(output_path, dpi=300, bbox_inches='tight')
    # print(f"Memory load plot saved to: {output_path}")
    # plt.show()

def plot_pending_pods(df, output_dir):
    """Plot stacked area for pending pods (private/public) over time, with hatching."""
    plt.figure(figsize=(12, 6))
    x = df['timestamp']
    y_private = df['number_pending_private'].fillna(0)
    y_public = df['number_pending_public'].fillna(0)

    plt.fill_between(
        x, 0, y_private,
        label="Pending Private",
        color='tab:blue',
        alpha=0.4,
        hatch='//',
        edgecolor='tab:blue'
    )

    plt.fill_between(
        x, y_private, y_private + y_public,
        label="Pending Public",
        color='tab:orange',
        alpha=0.4,
        hatch='\\\\',
        edgecolor='tab:orange'
    )

    plt.plot(x, y_private + y_public, label="Total Pending", color='black', marker='o')
    plt.title("Total Pending Pods over time (Stacked Private/Public)")
    plt.ylabel("Pending Pods")
    plt.xlabel("Time")
    ax = plt.gca()
    ax.xaxis.set_major_locator(mdates.AutoDateLocator())
    ax.xaxis.set_major_formatter(mdates.DateFormatter('%H:%M'))
    plt.xticks(rotation=45)
    plt.legend()
    plt.tight_layout()
    
    # Save the plot
    output_path = os.path.join(output_dir, "pending_pods.png")
    plt.savefig(output_path, dpi=300, bbox_inches='tight')
    # print(f"Pending pods plot saved to: {output_path}")
    # plt.show()

def plot_total_percent_pending(df, output_dir):
    """Plot total percent pending over time."""
    plt.figure(figsize=(12, 6))
    sns.lineplot(x="timestamp", y="total_percent_pending", data=df, label="Total Percent Pending", marker="o")
    plt.title("Total Percent Pending over time")
    plt.ylabel("Total Percent Pending (%)")
    plt.xlabel("Time")
    ax = plt.gca()
    ax.xaxis.set_major_locator(mdates.AutoDateLocator())
    ax.xaxis.set_major_formatter(mdates.DateFormatter('%H:%M'))
    plt.xticks(rotation=45)
    plt.legend()
    plt.tight_layout()
    
    # Save the plot
    output_path = os.path.join(output_dir, "total_percent_pending.png")
    plt.savefig(output_path, dpi=300, bbox_inches='tight')
    # print(f"Total percent pending plot saved to: {output_path}")
    # plt.show()

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
