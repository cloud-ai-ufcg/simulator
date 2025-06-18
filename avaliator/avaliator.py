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
            "total_percent_pending": data["total_percent_pending"]
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
    """Plot total pending pods percentage over time."""
    plt.figure(figsize=(12, 6))
    sns.lineplot(x="timestamp", y="total_percent_pending", data=df, label="Total Pending Percentage", marker="o")
    plt.title("Total Pending Pods Percentage over time")
    plt.ylabel("Pending Pods (%)")
    plt.xlabel("Time")
    plt.xticks(df['timestamp'], df['time_str'], rotation=0)
    plt.legend()
    plt.tight_layout()
    plt.show()

def main():
    """Main function to run the analysis."""
    sns.set_theme(style="whitegrid")
    
    json_path = "./data/example.json"
    
    df = load_data(json_path)
    
    plot_cpu_load(df)
    plot_memory_load(df)
    plot_pending_pods(df)

if __name__ == "__main__":
    main()
