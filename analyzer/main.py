"""
Migration Simulator Analyzer

This module provides the main entry point for analyzing migration simulation data.
Now using a refactored architecture with clear separation between data processing
and visualization.

Pipeline:
1. Load: Read JSON and log files
2. Process: Convert raw data into structured models
3. Prepare: Transform models into DataFrames for plotting
4. Visualize: Generate plots
5. Summarize: Generate statistical summaries
"""

import os
import sys
import json
import argparse
import pandas as pd
from data_loader import load_json_data, parse_migration_logs
from data_processor import (
    process_simulation_data,
    process_resources,
    process_cluster_info,
    build_dataframe,
    process_pricing_data,
    process_json_data,
    process_network_io_data
)
from plot_data_builder import (
    build_resource_dataframe,
    build_load_dataframe,
    build_pricing_dataframe,
    build_migration_dataframe,
    build_summary_input_data
)
from plotter import (
    plot_cpu_load,
    plot_memory_load,
    plot_total_percent_pending,
    plot_resource,
    plot_pricing,
    plot_network_load,
    plot_io_load
)
from metrics_summarizer import summarize


def main():
    """Main function to run the analysis and generate plots."""
    # Setup argument parser
    parser = argparse.ArgumentParser(
        description='Multi-Cloud Workload Migration Analyzer',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  python main.py ../simulator/data/output/20251113_163427 --mode kwok
  python main.py ../simulator/data/output/20251113_163427 --mode real
  
Modes:
  kwok  - KWOK mode: metrics are percentages (0-1)
  real  - Real mode: metrics are absolute values from cAdvisor
        """
    )
    parser.add_argument('run_directory', 
                        help='Path to the simulation run directory containing metrics.json')
    parser.add_argument('--mode', '-m',
                        choices=['kwok', 'real'],
                        required=True,
                        help='Execution mode: kwok (simulated) or real (cAdvisor metrics)')
    
    args = parser.parse_args()
    run_dir = args.run_directory
    execution_mode = args.mode
    
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
    processed_data_dir = os.path.join(analyzer_dir, "output", run_name, "processed_data")
    
    # Create output directories
    os.makedirs(plots_dir, exist_ok=True)
    os.makedirs(summary_dir, exist_ok=True)
    os.makedirs(processed_data_dir, exist_ok=True)
    
    try:
        print("📖 Loading data...")
        # Step 1: Load raw data
        raw_data = load_json_data(json_path)
        
        # Use the mode specified by the user
        print(f"🎯 Using execution mode: {execution_mode.upper()}")
        
        # Try to load migration data if actuator.log exists
        migration_df = None
        if os.path.exists(actuator_log_path):
            migration_df = parse_migration_logs(actuator_log_path)
            print(f"✓ Loaded migration data from {actuator_log_path}")
        else:
            print(f"Warning: actuator.log not found at {actuator_log_path}, continuing without migration data")

        # Process data using legacy functions (for compatibility with existing plots)
        timestamps, mem_allocated, mem_requested, cpu_allocated, cpu_requested, pending_pods = process_resources(raw_data, execution_mode)
        
        cluster_info_alloc = process_cluster_info(raw_data, timestamps, limit_load=True, execution_mode=execution_mode)
        df_alloc = build_dataframe(timestamps, mem_allocated, mem_requested, cpu_allocated, cpu_requested, pending_pods, cluster_info_alloc)
        
        cluster_info_req = process_cluster_info(raw_data, timestamps, limit_load=False, execution_mode=execution_mode)
        df_req = build_dataframe(timestamps, mem_allocated, mem_requested, cpu_allocated, cpu_requested, pending_pods, cluster_info_req)

        plot_resource(df_alloc, ['mem_allocated_public', 'mem_allocated_private'], ['cluster_memory_capacity_public', 'cluster_memory_capacity_private'], ['number_pending_private', 'number_pending_public'], 'Memory Allocated', os.path.join(plots_dir, 'allocated_memory.png'), migration_df)
        plot_resource(df_req, ['mem_requested_public', 'mem_requested_private'], ['cluster_memory_capacity_public', 'cluster_memory_capacity_private'], ['number_pending_private', 'number_pending_public'], 'Memory Requested', os.path.join(plots_dir, 'requested_memory.png'), migration_df)
        plot_resource(df_alloc, ['cpu_allocated_public', 'cpu_allocated_private'], ['cluster_cpu_capacity_public', 'cluster_cpu_capacity_private'], ['number_pending_private', 'number_pending_public'], 'CPU Allocated', os.path.join(plots_dir, 'allocated_cpu.png'), migration_df)
        plot_resource(df_req, ['cpu_requested_public', 'cpu_requested_private'], ['cluster_cpu_capacity_public', 'cluster_cpu_capacity_private'], ['number_pending_private', 'number_pending_public'], 'CPU Requested', os.path.join(plots_dir, 'requested_cpu.png'), migration_df)

        # Process data using new structured approach for pricing and other metrics
        processed_data = process_simulation_data(raw_data, migration_df, run_name, execution_mode)
        
        # Process and plot pricing data
        df_pricing, instance_types = build_pricing_dataframe(processed_data)
        plot_pricing(df_pricing, plots_dir, migration_df, instance_types)

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
        
        # Process and plot network and I/O metrics (only in REAL mode)
        if execution_mode == 'real':
            network_io_data = process_network_io_data(raw_data, timestamps, execution_mode)
            
            # Build DataFrame for network and I/O
            network_io_records = []
            for ts in timestamps:
                ts_str = str(ts)
                # Get index for this timestamp
                idx = timestamps.index(ts) if ts in timestamps else 0
                
                record = {
                    'timestamp': pd.to_datetime(ts, unit='s'),
                    'network_receive_private': network_io_data['network_receive_private'][idx] if idx < len(network_io_data['network_receive_private']) else 0.0,
                    'network_receive_public': network_io_data['network_receive_public'][idx] if idx < len(network_io_data['network_receive_public']) else 0.0,
                    'network_transmit_private': network_io_data['network_transmit_private'][idx] if idx < len(network_io_data['network_transmit_private']) else 0.0,
                    'network_transmit_public': network_io_data['network_transmit_public'][idx] if idx < len(network_io_data['network_transmit_public']) else 0.0,
                    'io_read_private': network_io_data['io_read_private'][idx] if idx < len(network_io_data['io_read_private']) else 0.0,
                    'io_read_public': network_io_data['io_read_public'][idx] if idx < len(network_io_data['io_read_public']) else 0.0,
                    'io_write_private': network_io_data['io_write_private'][idx] if idx < len(network_io_data['io_write_private']) else 0.0,
                    'io_write_public': network_io_data['io_write_public'][idx] if idx < len(network_io_data['io_write_public']) else 0.0,
                }
                network_io_records.append(record)
            
            df_network_io = pd.DataFrame(network_io_records)
            if not df_network_io.empty:
                # Calculate time_seconds from timestamp (same method as other plots)
                start_time = df_network_io['timestamp'].min()
                df_network_io['time_seconds'] = (df_network_io['timestamp'] - start_time).dt.total_seconds()
                
                plot_network_load(df_network_io, plots_dir, migration_df)
                plot_io_load(df_network_io, plots_dir, migration_df)
                print(f"✓ Network and I/O plots generated (REAL mode)")
        
        summarize(raw_data, summary_dir, migration_df)
        
        print(f"\n✅ Analysis complete!")
        print(f"📊 Plots saved to: {plots_dir}")
        print(f"📈 Summary saved to: {summary_dir}")
        print(f"💾 Processed data saved to: {processed_data_dir}")
        print(f"\n📌 Summary:")
        print(f"   - Execution mode: {execution_mode.upper()}")
        print(f"   - Timestamps processed: {len(processed_data.timestamps)}")
        print(f"   - Interval duration: {processed_data.interval_duration}s")
        print(f"   - Migration events: {len(processed_data.migration_events)}")
        print(f"   - Total cumulative cost: ${processed_data.get_cumulative_cost_total():.4f}")
        
        # Print cluster-specific costs
        for label in ['public', 'private']:
            cost = processed_data.get_cumulative_cost_by_label(label)
            print(f"   - {label.capitalize()} cluster cost: ${cost:.4f}")
            if 'instance_types' in locals() and label in instance_types:
                print(f"     Instance type: {instance_types[label]}")

    except FileNotFoundError as e:
        print(f"❌ Error: File not found: {e}")
        sys.exit(1)
    except Exception as e:
        print(f"❌ An unexpected error occurred: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)


if __name__ == "__main__":
    main()
