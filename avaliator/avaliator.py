import sys
import pandas as pd
import matplotlib.pyplot as plt
import seaborn as sns
from datetime import datetime
import json

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
            "number_pending_public": data["number_pending_public"]
        })
    
    df = pd.DataFrame(records)
    df['time_str'] = df['timestamp'].dt.strftime('%H:%M')
    return df

def plot_cpu_load(df):
    """Plot CPU load by cluster over time."""
    plt.figure(figsize=(12, 6))
    sns.lineplot(x="timestamp", y="cpu_load_private", data=df, label="CPU Load Private", marker="o")
    sns.lineplot(x="timestamp", y="cpu_load_public", data=df, label="CPU Load Public", marker="o")
    plt.title("CPU Load by Cluster over time")
    plt.ylabel("CPU Load")
    plt.xlabel("Time")
    plt.xticks(df['timestamp'], df['time_str'], rotation=0)
    plt.legend()
    plt.tight_layout()
    plt.show()

def plot_memory_load(df):
    """Plot memory load by cluster over time."""
    plt.figure(figsize=(12, 6))
    sns.lineplot(x="timestamp", y="mem_load_private", data=df, label="Mem Load Private", marker="o")
    sns.lineplot(x="timestamp", y="mem_load_public", data=df, label="Mem Load Public", marker="o")
    plt.title("Memory Load by Cluster over time")
    plt.ylabel("Memory Load")
    plt.xlabel("Time")
    plt.xticks(df['timestamp'], df['time_str'], rotation=0)
    plt.legend()
    plt.tight_layout()
    plt.show()

def plot_pending_pods(df):
    """Plot stacked area for pending pods (private/public) over time, with hatching."""
    plt.figure(figsize=(12, 6))

    x = df['time_str']
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
    plt.legend()
    plt.tight_layout()
    plt.show()

def main():
    """Main function to run the analysis."""
    sns.set_theme(style="whitegrid")

    if len(sys.argv) != 2:
        print("Usage: python avaliator.py <input_json_file>")
        sys.exit(1)
    
    json_path = sys.argv[1]
    
    try:
        df = load_data(json_path)
        plot_cpu_load(df)
        plot_memory_load(df)
        plot_pending_pods(df)
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
