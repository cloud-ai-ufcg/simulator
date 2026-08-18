#!/usr/bin/env python3
"""Aggregate summary_metrics_*.csv from multiple runs per scenario.

A scenario = (model, load, temperature). Repeated runs of the same scenario
live in sibling directories that share the same base name, differing only by
a timestamp suffix (e.g. anthropic-claude-sonnet-4.5_input_varia_v2_1_20260802_080813).

Usage:
    python aggregate_scenario_metrics.py [--root DIR] [--output CSV]
"""

import argparse
import re
import sys
from pathlib import Path

import pandas as pd

EXPECTED_METRICS = [
    "cost", "cpu_usage", "mem_usage", "pending_pods", "time_with_pending",
    "wokloads_with_pending_pods", "number_of_migrations",
]

# LLM-scheduled runs: "{model}_input_{load}_v{graph}_{temperature}[_YYYYMMDD_HHMMSS]"
# e.g. openai-gpt-5_input_varia_v2_0_20260801_141602 -> model=openai-gpt-5, load=varia, temperature=0
LLM_RE = re.compile(
    r"^(?P<model>.+?)_input_(?P<load>const|varia)_v\d+_(?P<temp>[\d.]+)(?:_\d{8}_\d{6})?$"
)
# Baseline runs (native Karmada scheduler, no LLM): "baseline_input_{load}[_YYYYMMDD_HHMMSS]"
BASELINE_RE = re.compile(r"^baseline_input_(?P<load>const|varia)(?:_\d{8}_\d{6})?$")


def extract_scenario(run_dir_name: str):
    """Extract (model, load, temperature) from the run directory name.

    The run directory is always the immediate parent of "summary/". It can
    be nested at any depth (e.g. runs_baseline_test/<name>), so only the
    basename matters for identifying the scenario.

    Returns None if the name doesn't match any known pattern — the caller
    decides how to report that as an error.
    """
    m = LLM_RE.match(run_dir_name)
    if m:
        return m.group("model"), m.group("load"), float(m.group("temp"))

    m = BASELINE_RE.match(run_dir_name)
    if m:
        return "karmada-native", m.group("load"), "N/A"

    return None


def _self_check():
    """python aggregate_scenario_metrics.py --selftest: validates extract_scenario against real names seen in the data."""
    cases = [
        ("openai-gpt-5_input_varia_v2_0_20260801_141602", ("openai-gpt-5", "varia", 0.0)),
        ("anthropic-claude-sonnet-4.5_input_const_v2_1_20260803_141110", ("anthropic-claude-sonnet-4.5", "const", 1.0)),
        ("google-gemini-2.5-pro_input_const_v1_0", ("google-gemini-2.5-pro", "const", 0.0)),
        ("baseline_input_const_20260801_030850", ("karmada-native", "const", "N/A")),
        ("baseline_input_varia", ("karmada-native", "varia", "N/A")),
        ("20260730_120802_Baseline", None),
        ("runs (plots incorretos)", None),
    ]
    for name, expected in cases:
        actual = extract_scenario(name)
        assert actual == expected, f"{name!r}: expected {expected!r}, got {actual!r}"
    print("self-check ok")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", default=".", help="Root directory to search (default: .)")
    parser.add_argument("--output", default="scenario_summary.csv", help="Output CSV path")
    parser.add_argument("--load", choices=["const", "varia"], help="Keep only scenarios with this load (default: both)")
    parser.add_argument("--selftest", action="store_true", help="Run the extract_scenario self-check and exit")
    args = parser.parse_args()

    if args.selftest:
        _self_check()
        return

    root = Path(args.root)
    # Only consider runs directly at <root>/<run_dir>/summary/*.csv.
    # Wrapper folders like runs_baseline_test/ or "runs (plots incorretos)/"
    # add an extra directory level before "summary/" and are skipped.
    files = sorted(root.glob("*/summary/summary_metrics_*.csv"))
    if not files:
        print(f"No summary_metrics_*.csv found under {root}", file=sys.stderr)
        sys.exit(1)

    # Group by scenario: each (model, load, temperature) key accumulates a
    # list of DataFrames, one per run/repetition found.
    groups: dict[tuple, list[pd.DataFrame]] = {}
    errors: list[str] = []

    for path in files:
        run_dir = path.parent.parent  # .../<run_dir>/summary/summary_metrics_*.csv
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

        missing = set(EXPECTED_METRICS) - set(df.index)
        if missing:
            errors.append(f"{path}: missing metrics {sorted(missing)} (processing the rest)")

        groups.setdefault(scenario, []).append(df)

    if errors:
        print("Warnings/errors during processing:", file=sys.stderr)
        for e in errors:
            print(f"  - {e}", file=sys.stderr)

    # For each scenario and metric, aggregate across runs:
    #   mean_across_runs   = average of each run's 'mean' column (mean of means)
    #   min_across_runs    = average of each run's 'min' column
    #   max_across_runs    = average of each run's 'max' column
    #   median_across_runs = average of each run's 'median' column
    #   std_across_runs    = standard deviation of the per-run means
    #                        (measures consistency between repetitions, not the
    #                        variability within a single run)
    rows = []
    for (model, load, temperature), dfs in groups.items():
        for metric in EXPECTED_METRICS:
            values = [df.loc[metric] for df in dfs if metric in df.index]
            if not values:
                continue
            means = pd.Series([v["mean"] for v in values])
            mins = pd.Series([v["min"] for v in values])
            maxs = pd.Series([v["max"] for v in values])
            medians = pd.Series([v["median"] for v in values])
            rows.append({
                "model": model,
                "temperature": temperature,
                "load": load,
                "metric": metric,
                "mean_across_runs": means.mean(),
                "min_across_runs": mins.mean(),
                "max_across_runs": maxs.mean(),
                "median_across_runs": medians.mean(),
                "std_across_runs": means.std(ddof=1) if len(means) > 1 else 0.0,
                "n_runs": len(values),
            })

    result = pd.DataFrame(rows).sort_values(
        ["model", "load", "temperature", "metric"]
    ).reset_index(drop=True)

    result.to_csv(args.output, index=False)
    print(f"\n{len(files)} files read, {len(groups)} scenarios, {len(errors)} warnings.")
    print(f"CSV saved to: {args.output}\n")

    with pd.option_context("display.max_rows", None, "display.width", 160):
        print(result.to_string(index=False))


if __name__ == "__main__":
    main()
