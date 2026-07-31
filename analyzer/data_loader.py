import json
import re
import pandas as pd
from datetime import datetime

def load_json_data(filepath):
    """Loads JSON data from a file."""
    with open(filepath) as f:
        return json.load(f)


def load_unschedulable_data(filepath):
    """
    Loads unschedulable_bindings.jsonl — one JSON object per line, written by
    simulator/internal/baseline.UnschedulablePoller's polling loop while
    the simulator runs (started from cmd/main.go under WASP_DISABLE_AI):
        {"timestamp": "2026-07-20 21:34:59", "unschedulable_count": 2,
         "unschedulable_workloads": ["default/12-345-deployment", ...]}

    These are ResourceBindings karmada-scheduler couldn't assign to *any*
    cluster (status.conditions Scheduled=False) — a workload whose desired
    replica count doesn't fit anywhere never gets propagated, so it never
    shows up as a Pending pod in metrics.json. Only produced for baseline
    runs today; returns an empty DataFrame (not an error) if the file is
    missing, e.g. for a normal AI-driven run.

    Returns a DataFrame with columns: timestamp (unix int), unschedulable_count,
    unschedulable_workloads (list).
    """
    columns = ['timestamp', 'unschedulable_count', 'unschedulable_workloads']
    rows = []
    try:
        with open(filepath) as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                entry = json.loads(line)
                dt = datetime.strptime(entry['timestamp'], '%Y-%m-%d %H:%M:%S')
                rows.append({
                    'timestamp': int(dt.timestamp()),
                    'unschedulable_count': int(entry.get('unschedulable_count', 0)),
                    'unschedulable_workloads': entry.get('unschedulable_workloads', []),
                })
    except FileNotFoundError:
        return pd.DataFrame(columns=columns)

    return pd.DataFrame(rows) if rows else pd.DataFrame(columns=columns)

# Individual per-workload relabel line, e.g.:
#   2026/07/17 23:20:24 🔄 Deployment default/77 updated to member2
WORKLOAD_LINE_PATTERN = re.compile(
    r'^(\d{4}/\d{2}/\d{2} \d{2}:\d{2}:\d{2}) .*🔄 \w+ \S+ updated to (\S+)'
)

# Current batch-summary line, e.g.:
#   2026/07/17 23:20:36 [KARMADA] Migration Summary - Execution: 1 | Label type: Mixed | Total migrated pods: 108
# Note: unlike the older formats below, this one no longer breaks the total
# down by destination — that breakdown is reconstructed here by counting the
# 🔄 lines (per-workload, not per-pod) collected since the previous summary.
CURRENT_FORMAT_PATTERN = re.compile(
    r'^(\d{4}/\d{2}/\d{2} \d{2}:\d{2}:\d{2}).*\[KARMADA\]\s+Migration Summary.*Execution:\s+(\d+).*Total migrated pods:\s+(\d+)'
)

def parse_migration_logs(log_filepath):
    """
    Extracts one row per migration execution batch from the actuator log.

    Supports three formats, oldest first:
    - Old format: 2025/09/20 15:30:45 📊 Migration Summary - Execution: 1 | Label type: public | Total migrated pods: 15 | To Private: 10 pods | To Public: 5 pods
    - Mid format: 2025/11/21 18:34:43 [KARMADA] Migration Summary - Execution: 1 | Label type: private | Total migrated pods: 1 | To Private: 1 | To Public: 0
    - Current format (member1/member2 clusters, no per-destination totals):
        2026/07/17 23:20:24 🔄 Deployment default/77 updated to member2
        ...
        2026/07/17 23:20:36 [KARMADA] Migration Summary - Execution: 1 | Label type: Mixed | Total migrated pods: 108

    For the current format, 'type' and the migrated_to_private/public split
    are derived from the 🔄 lines belonging to that execution (member1 is
    "private", member2 is "public" — same convention monitor/config.yaml
    uses for cluster_profile), so downstream code (plotter.py's
    private/public/both/no-migration legend) keeps working unchanged. The
    split counts workloads relabeled, not pods migrated — actuator.log
    doesn't record per-workload replica counts, only the batch total does.
    """
    old_format_pattern = re.compile(
        r'^(\d{4}/\d{2}/\d{2} \d{2}:\d{2}:\d{2}).*📊\s+Migration Summary.*Execution:\s+(\d+).*Label type:\s+([^|]+).*Total migrated pods:\s+(\d+).*To Private:\s+(\d+)\s+pods.*To Public:\s+(\d+)\s+pods'
    )
    mid_format_pattern = re.compile(
        r'^(\d{4}/\d{2}/\d{2} \d{2}:\d{2}:\d{2}).*\[KARMADA\]\s+Migration Summary.*Execution:\s+(\d+).*Label type:\s+([^|]+).*Total migrated pods:\s+(\d+).*To Private:\s+(\d+).*To Public:\s+(\d+)'
    )

    columns = ['execution', 'type', 'timestamp', 'total_migrated_pods',
               'migrated_to_private', 'migrated_to_public']
    migrations = []
    batch_destinations = []  # 'member1'/'member2' for each 🔄 line since the last summary

    try:
        with open(log_filepath, 'r') as f:
            for line in f:
                mid_match = mid_format_pattern.search(line)
                old_match = None if mid_match else old_format_pattern.search(line)
                if mid_match or old_match:
                    match = mid_match or old_match
                    dt = datetime.strptime(match.group(1), '%Y/%m/%d %H:%M:%S')
                    migrations.append({
                        'execution': int(match.group(2)),
                        'type': match.group(3).strip(),
                        'timestamp': int(dt.timestamp()),
                        'total_migrated_pods': int(match.group(4)),
                        'migrated_to_private': int(match.group(5)),
                        'migrated_to_public': int(match.group(6)),
                    })
                    batch_destinations = []
                    continue

                workload_match = WORKLOAD_LINE_PATTERN.match(line)
                if workload_match:
                    batch_destinations.append(workload_match.group(2))
                    continue

                current_match = CURRENT_FORMAT_PATTERN.search(line)
                if current_match:
                    to_private = sum(1 for c in batch_destinations if c == 'member1')
                    to_public = sum(1 for c in batch_destinations if c == 'member2')
                    if to_private and to_public:
                        label_type = 'both'
                    elif to_private:
                        label_type = 'private'
                    elif to_public:
                        label_type = 'public'
                    else:
                        label_type = 'no migration'

                    dt = datetime.strptime(current_match.group(1), '%Y/%m/%d %H:%M:%S')
                    migrations.append({
                        'execution': int(current_match.group(2)),
                        'type': label_type,
                        'timestamp': int(dt.timestamp()),
                        'total_migrated_pods': int(current_match.group(3)),
                        'migrated_to_private': to_private,
                        'migrated_to_public': to_public,
                    })
                    batch_destinations = []

    except FileNotFoundError:
        print(f"Warning: Migration log file not found at {log_filepath}. Continuing without migration data.")
        return pd.DataFrame(columns=columns)

    return pd.DataFrame(migrations) if migrations else pd.DataFrame(columns=columns)
