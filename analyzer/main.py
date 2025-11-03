"""
Migration Simulator Analyzer

This module provides the main entry point for analyzing migration simulation data.
It processes JSON data, generates various plots for resource utilization analysis,
and helps visualize cluster metrics and migration patterns.
"""

import os
import sys
import json
import pandas as pd
from metrics_summarizer import summarize
from data_loader import load_json_data, parse_migration_logs
from data_processor import process_json_data, process_resources, process_cluster_info, build_dataframe, process_pricing_data, build_pricing_dataframe
from plotter import plot_cpu_load, plot_memory_load, plot_total_percent_pending, plot_resource, plot_pricing

def main():
    """Main function to run the analysis and generate plots."""
    if len(sys.argv) != 2:
        print("Usage: python main.py <run_directory>")
        print("")
        print("The run directory should contain:")
        print("  - metrics.json (required)")
        print("  - logs/actuator.log (optional, for migration tracking)")
        sys.exit(1)

    run_dir = sys.argv[1]
    
    # Verify run directory exists
    if not os.path.isdir(run_dir):
        print(f"Error: Directory '{run_dir}' not found.")
        sys.exit(1)
    
    # Get paths
    json_path = os.path.join(run_dir, "metrics.json")
    actuator_log_path = os.path.join(run_dir, "logs", "actuator.log")
    
    # Verify metrics.json exists
    if not os.path.exists(json_path):
        print(f"Error: metrics.json not found in '{run_dir}'")
        sys.exit(1)
    
    # Extract timestamp from run directory name
    run_name = os.path.basename(os.path.normpath(run_dir))
    
    # Get the analyzer directory (where this script is located)
    analyzer_dir = os.path.dirname(os.path.abspath(__file__))
    plots_dir = os.path.join(analyzer_dir, "output", run_name, "plots")
    summary_dir = os.path.join(analyzer_dir, "output", run_name, "summary")
    
    if not os.path.exists(plots_dir):
        os.makedirs(plots_dir)
    
    if not os.path.exists(summary_dir):
        os.makedirs(summary_dir)
    try:
        raw_data = load_json_data(json_path)
        
        # Try to load migration data if actuator.log exists
        migration_data = []
        if os.path.exists(actuator_log_path):
            migration_data = parse_migration_logs(actuator_log_path)
            print(f"Loaded migration data from {actuator_log_path}")
        else:
            print(f"Warning: actuator.log not found at {actuator_log_path}, continuing without migration data")

        timestamps, mem_allocated, mem_requested, cpu_allocated, cpu_requested, pending_pods = process_resources(raw_data)
        
        cluster_info_alloc = process_cluster_info(raw_data, timestamps, limit_load=True)
        df_alloc = build_dataframe(timestamps, mem_allocated, mem_requested, cpu_allocated, cpu_requested, pending_pods, cluster_info_alloc)
        
        cluster_info_req = process_cluster_info(raw_data, timestamps, limit_load=False)
        df_req = build_dataframe(timestamps, mem_allocated, mem_requested, cpu_allocated, cpu_requested, pending_pods, cluster_info_req)

        plot_resource(df_alloc, ['mem_allocated_public', 'mem_allocated_private'], ['cluster_memory_capacity_public', 'cluster_memory_capacity_private'], ['number_pending_private', 'number_pending_public'], 'Memory Allocated', os.path.join(plots_dir, 'allocated_memory.png'), migration_data)
        plot_resource(df_req, ['mem_requested_public', 'mem_requested_private'], ['cluster_memory_capacity_public', 'cluster_memory_capacity_private'], ['number_pending_private', 'number_pending_public'], 'Memory Requested', os.path.join(plots_dir, 'requested_memory.png'), migration_data)
        plot_resource(df_alloc, ['cpu_allocated_public', 'cpu_allocated_private'], ['cluster_cpu_capacity_public', 'cluster_cpu_capacity_private'], ['number_pending_private', 'number_pending_public'], 'CPU Allocated', os.path.join(plots_dir, 'allocated_cpu.png'), migration_data)
        plot_resource(df_req, ['cpu_requested_public', 'cpu_requested_private'], ['cluster_cpu_capacity_public', 'cluster_cpu_capacity_private'], ['number_pending_private', 'number_pending_public'], 'CPU Requested', os.path.join(plots_dir, 'requested_cpu.png'), migration_data)

        # Process and plot pricing data
        pricing_timestamps, pricing_data = process_pricing_data(raw_data)
        df_pricing, instance_types = build_pricing_dataframe(pricing_timestamps, pricing_data)
        plot_pricing(df_pricing, plots_dir, migration_data, instance_types)

        processed_data_for_summary = process_json_data(raw_data)
        records = []
        sorted_ts = sorted(processed_data_for_summary.keys(), key=int)
        for ts_str in sorted_ts:
            ts = int(ts_str)
            data = processed_data_for_summary[ts_str]
            records.append({
                "timestamp": pd.to_datetime(ts, unit='s'),
                "cpu_load_private": data["cluster_load_cpu"].get("private", 0),
                "cpu_load_public": data["cluster_load_cpu"].get("public", 0),
                "mem_load_private": data["cluster_load_memory"].get("private", 0),
                "mem_load_public": data["cluster_load_memory"].get("public", 0),
                "number_of_pods_pending": data["number_of_pods_pending"],
                "number_pending_private": data["number_pending_private"],
                "number_pending_public": data["number_pending_public"],
                "total_percent_pending": data["total_percent_pending"],
            })
        df_summary = pd.DataFrame(records)
        if not df_summary.empty:
            start_time = df_summary['timestamp'].min()
            df_summary['time_seconds'] = (df_summary['timestamp'] - start_time).dt.total_seconds()
        else:
            df_summary['time_seconds'] = pd.Series(dtype='float64')

        plot_cpu_load(df_summary, plots_dir)
        plot_memory_load(df_summary, plots_dir)
        plot_total_percent_pending(df_summary, plots_dir)
        summarize(raw_data, summary_dir, migration_data)
        
        print(f"\n✅ Analysis complete!")
        print(f"📊 Plots saved to: {plots_dir}")
        print(f"📈 Summary saved to: {summary_dir}")

    except FileNotFoundError as e:
        print(f"Error: File not found: {e}")
        sys.exit(1)
    except json.JSONDecodeError as e:
        print(f"Error: Invalid JSON format in '{json_path}': {e}")
        sys.exit(1)
    except Exception as e:
        print(f"An unexpected error occurred: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)

if __name__ == "__main__":
    main()
