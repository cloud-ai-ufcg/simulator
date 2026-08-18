#!/usr/bin/env python3
"""Concatenate every summary_metrics_*.csv into a single CSV, tagged by run.

Unlike aggregate_scenario_metrics.py (one row per scenario+metric, averaged
across repetitions), this script does no aggregation: it just stacks each
run's summary_metrics.csv rows (one per metric) together, prefixed with the
scenario/run it came from.

Usage:
    python list_scenario_runs.py [--root DIR] [--output CSV]
"""

import argparse
import sys
from pathlib import Path

import pandas as pd

from aggregate_scenario_metrics import extract_scenario


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", default=".", help="Root directory to search (default: .)")
    parser.add_argument("--output", default="scenario_runs.csv", help="Output CSV path")
    parser.add_argument("--load", choices=["const", "varia"], help="Keep only scenarios with this load (default: both)")
    args = parser.parse_args()

    root = Path(args.root)
    # Same discovery rule as aggregate_scenario_metrics.py: only one level of
    # nesting (<root>/<run_dir>/summary/*.csv), wrapper folders are skipped.
    files = sorted(root.glob("*/summary/summary_metrics_*.csv"))
    if not files:
        print(f"No summary_metrics_*.csv found under {root}", file=sys.stderr)
        sys.exit(1)

    chunks = []
    errors = []
    for path in files:
        run_dir = path.parent.parent
        scenario = extract_scenario(run_dir.name)
        if scenario is None:
            errors.append(f"unidentifiable scenario from '{run_dir.name}' ({path})")
            continue
        if args.load and scenario[1] != args.load:
            continue

        try:
            df = pd.read_csv(path, index_col=0)
        except Exception as e:
            errors.append(f"failed to read {path}: {e}")
            continue

        model, load, temperature = scenario
        df = df.rename_axis("metric").reset_index()
        df.insert(0, "run_dir", run_dir.name)
        df.insert(0, "load", load)
        df.insert(0, "temperature", temperature)
        df.insert(0, "model", model)
        chunks.append(df)

    if errors:
        print("Warnings/errors during processing:", file=sys.stderr)
        for e in errors:
            print(f"  - {e}", file=sys.stderr)

    result = pd.concat(chunks, ignore_index=True).sort_values(
        ["model", "load", "temperature", "run_dir", "metric"]
    ).reset_index(drop=True)

    result.to_csv(args.output, index=False)
    print(f"\n{len(files)} files read, {len(chunks)} runs, {len(result)} rows, {len(errors)} warnings.")
    print(f"CSV saved to: {args.output}\n")

    with pd.option_context("display.max_rows", None, "display.width", 200):
        print(result.to_string(index=False))


if __name__ == "__main__":
    main()
