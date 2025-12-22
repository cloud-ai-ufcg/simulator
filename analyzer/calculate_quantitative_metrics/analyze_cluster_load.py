#!/usr/bin/env python3
"""Analyze cluster load metrics - count how many times they exceed 80%."""

import pandas as pd
from pathlib import Path

# Read CSV file
csv_file = "output/google-gemini-2.5-pro_input_const_v1_0.1/20251218_081553/summary/summary_metrics_2025-12-18-08-16-08.csv"

print(f"Reading CSV file: {csv_file}")
df = pd.read_csv(csv_file)

# Columns to analyze
load_columns = [
    "cluster_mem_load_public",
    "cluster_cpu_load_public",
    "cluster_mem_load_private",
    "cluster_cpu_load_private"
]

print("\n=== Cluster Load Analysis (> 80%) ===\n")

results = []

for col in load_columns:
    if col in df.columns:
        # Count values > 80
        count_above_80 = (df[col] > 80).sum()
        total = df[col].notna().sum()
        percentage = (count_above_80 / total * 100) if total > 0 else 0
        
        results.append({
            "Metric": col,
            "Count_Above_80": count_above_80,
            "Total_Measurements": total,
            "Percentage": round(percentage, 2)
        })
        
        print(f"{col:30s}: {count_above_80:4d} / {total:4d} measurements ({percentage:.2f}%)")
    else:
        print(f"Column not found: {col}")

print("\n=== Summary Table ===")
results_df = pd.DataFrame(results)
print(results_df.to_string(index=False))

# Save results to CSV
output_file = csv_file.replace('.csv', '_load_analysis.csv')
results_df.to_csv(output_file, index=False)
print(f"\n✅ Results saved to: {output_file}")

# Additional statistics
print("\n=== Additional Statistics ===")
for col in load_columns:
    if col in df.columns:
        values = df[col].dropna()
        print(f"\n{col}:")
        print(f"  Min:    {values.min():.2f}")
        print(f"  Mean:   {values.mean():.2f}")
        print(f"  Median: {values.median():.2f}")
        print(f"  Max:    {values.max():.2f}")
