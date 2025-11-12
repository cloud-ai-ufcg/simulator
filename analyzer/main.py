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
import pandas as pd
from data_loader import load_json_data, parse_migration_logs
from data_processor import process_simulation_data
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
    plot_pricing
)
from metrics_summarizer import summarize


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
    processed_data_dir = os.path.join(analyzer_dir, "output", run_name, "processed_data")
    
    # Create output directories
    os.makedirs(plots_dir, exist_ok=True)
    os.makedirs(summary_dir, exist_ok=True)
    os.makedirs(processed_data_dir, exist_ok=True)
    
    try:
        print("📖 Loading data...")
        # Step 1: Load raw data
        raw_data = load_json_data(json_path)
        
        # Try to load migration data if actuator.log exists
        migration_df = None
        if os.path.exists(actuator_log_path):
            migration_df = parse_migration_logs(actuator_log_path)
            print(f"✓ Loaded migration data from {actuator_log_path}")
        else:
            print(f"⚠ Warning: actuator.log not found at {actuator_log_path}")
            print("  Continuing without migration data")
        
        # Step 2: Process data into structured models
        print("⚙️  Processing data...")
        processed_data = process_simulation_data(raw_data, migration_df, run_name)
        print(f"✓ Processed {len(processed_data.timestamps)} timestamps")
        
        # Step 3: Prepare data for visualization
        print("📊 Preparing data for visualization...")
        
        # Build DataFrames for plotting
        df_resources = build_resource_dataframe(processed_data)
        df_load = build_load_dataframe(processed_data)
        df_pricing, instance_types = build_pricing_dataframe(processed_data)
        df_migrations = build_migration_dataframe(processed_data.migration_events)
        
        print(f"✓ Built DataFrames for visualization")
        
        # Save processed data to a single CSV
        print("💾 Saving processed data to CSV...")
        
        # Merge all dataframes on timestamp and time_seconds
        df_combined = df_resources.copy()
        
        # Merge load data (drop duplicate columns)
        load_cols_to_merge = [col for col in df_load.columns if col not in ['timestamp', 'time_seconds']]
        df_combined = df_combined.merge(
            df_load[['timestamp'] + load_cols_to_merge], 
            on='timestamp', 
            how='left'
        )
        
        # Merge pricing data (drop duplicate columns)
        pricing_cols_to_merge = [col for col in df_pricing.columns if col not in ['timestamp', 'time_seconds']]
        df_combined = df_combined.merge(
            df_pricing[['timestamp'] + pricing_cols_to_merge], 
            on='timestamp', 
            how='left'
        )
        
        # Merge migration data if exists
        if not df_migrations.empty:
            # Convert migration unix timestamp to datetime for merge
            df_migrations_for_merge = df_migrations.copy()
            df_migrations_for_merge['timestamp'] = pd.to_datetime(df_migrations_for_merge['timestamp'], unit='s')
            
            # Adjust timezone if needed (subtract 3 hours as done in plotter)
            df_migrations_for_merge['timestamp'] = df_migrations_for_merge['timestamp'] - pd.Timedelta(hours=3)
            
            # Rename columns to avoid conflicts
            df_migrations_for_merge = df_migrations_for_merge.rename(columns={
                'execution': 'migration_execution',
                'type': 'migration_type',
                'total_migrated_pods': 'migration_total_pods',
                'migrated_to_private': 'migration_to_private',
                'migrated_to_public': 'migration_to_public'
            })
            
            # Merge with left join (keep all timestamps, fill NaN for non-migration rows)
            df_combined = df_combined.merge(
                df_migrations_for_merge[['timestamp', 'migration_execution', 'migration_type', 
                                         'migration_total_pods', 'migration_to_private', 'migration_to_public']], 
                on='timestamp', 
                how='left'
            )
            
            print(f"✓ Merged {len(df_migrations)} migration events into combined data")
        
        # Save combined data
        combined_csv_path = os.path.join(processed_data_dir, 'processed_data.csv')
        df_combined.to_csv(combined_csv_path, index=False)
        
        print(f"✓ Saved processed data to: {combined_csv_path}")
        
        # Step 4: Generate visualizations
        print("🎨 Generating plots...")
        
        # Resource plots
        print("  - Allocated Memory...")
        plot_resource(
            df_resources,
            ['mem_allocated_public', 'mem_allocated_private'],
            ['cluster_memory_capacity_public', 'cluster_memory_capacity_private'],
            ['number_pending_private', 'number_pending_public'],
            'Memory Allocated',
            os.path.join(plots_dir, 'allocated_memory.png'),
            df_migrations if not df_migrations.empty else None
        )
        
        print("  - Requested Memory...")
        plot_resource(
            df_resources,
            ['mem_requested_public', 'mem_requested_private'],
            ['cluster_memory_capacity_public', 'cluster_memory_capacity_private'],
            ['number_pending_private', 'number_pending_public'],
            'Memory Requested',
            os.path.join(plots_dir, 'requested_memory.png'),
            df_migrations if not df_migrations.empty else None
        )
        
        print("  - Allocated CPU...")
        plot_resource(
            df_resources,
            ['cpu_allocated_public', 'cpu_allocated_private'],
            ['cluster_cpu_capacity_public', 'cluster_cpu_capacity_private'],
            ['number_pending_private', 'number_pending_public'],
            'CPU Allocated',
            os.path.join(plots_dir, 'allocated_cpu.png'),
            df_migrations if not df_migrations.empty else None
        )
        
        print("  - Requested CPU...")
        plot_resource(
            df_resources,
            ['cpu_requested_public', 'cpu_requested_private'],
            ['cluster_cpu_capacity_public', 'cluster_cpu_capacity_private'],
            ['number_pending_private', 'number_pending_public'],
            'CPU Requested',
            os.path.join(plots_dir, 'requested_cpu.png'),
            df_migrations if not df_migrations.empty else None
        )
        
        # Load plots
        print("  - CPU Load...")
        plot_cpu_load(df_load, plots_dir)
        
        print("  - Memory Load...")
        plot_memory_load(df_load, plots_dir)
        
        print("  - Pending Pods...")
        plot_total_percent_pending(df_load, plots_dir)
        
        # Pricing plot
        print("  - Pricing Analysis...")
        plot_pricing(
            df_pricing, 
            plots_dir, 
            df_migrations if not df_migrations.empty else None,
            instance_types
        )
        
        # Step 5: Generate summary statistics
        print("📈 Generating summary statistics...")
        summarize(raw_data, summary_dir, df_migrations if not df_migrations.empty else None)
        
        print(f"\n✅ Analysis complete!")
        print(f"📊 Plots saved to: {plots_dir}")
        print(f"📈 Summary saved to: {summary_dir}")
        print(f"💾 Processed data saved to: {processed_data_dir}")
        print(f"\n📌 Summary:")
        print(f"   - Timestamps processed: {len(processed_data.timestamps)}")
        print(f"   - Interval duration: {processed_data.interval_duration}s")
        print(f"   - Migration events: {len(processed_data.migration_events)}")
        print(f"   - Total cumulative cost: ${processed_data.get_cumulative_cost_total():.4f}")
        
        # Print cluster-specific costs
        for label in ['public', 'private']:
            cost = processed_data.get_cumulative_cost_by_label(label)
            print(f"   - {label.capitalize()} cluster cost: ${cost:.4f}")
            if label in instance_types:
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
