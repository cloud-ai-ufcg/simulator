import json
import re
import pandas as pd
from datetime import datetime

def load_json_data(filepath):
    """Loads JSON data from a file."""
    with open(filepath) as f:
        return json.load(f)

def parse_migration_logs(log_filepath):
    """
    Extracts the migration type, time, and pod migration details from the log, converting it to a Unix timestamp.
    Supports both old and new formats:
    - Old format: 2025/09/20 15:30:45 📊 Migration Summary - Execution: 1 | Label type: public | Total migrated pods: 15 | To Private: 10 pods | To Public: 5 pods
    - New format: 2025/11/21 18:34:43 [KARMADA] Migration Summary - Execution: 1 | Label type: private | Total migrated pods: 1 | To Private: 1 | To Public: 0
    """
    migrations = []
    
    # Pattern for new format: [KARMADA] Migration Summary (without "pods" suffix on numbers)
    # Example: 2025/11/21 18:34:43 [KARMADA] Migration Summary - Execution: 1 | Label type: private | Total migrated pods: 1 | To Private: 1 | To Public: 0
    new_format_pattern = re.compile(
        r'^(\d{4}/\d{2}/\d{2} \d{2}:\d{2}:\d{2}).*\[KARMADA\]\s+Migration Summary.*Execution:\s+(\d+).*Label type:\s+([^|]+).*Total migrated pods:\s+(\d+).*To Private:\s+(\d+).*To Public:\s+(\d+)'
    )
    
    # Pattern for old format: 📊 Migration Summary (with "pods" suffix on numbers)
    # Example: 2025/09/20 15:30:45 📊 Migration Summary - Execution: 1 | Label type: public | Total migrated pods: 15 | To Private: 10 pods | To Public: 5 pods
    old_format_pattern = re.compile(
        r'^(\d{4}/\d{2}/\d{2} \d{2}:\d{2}:\d{2}).*📊\s+Migration Summary.*Execution:\s+(\d+).*Label type:\s+([^|]+).*Total migrated pods:\s+(\d+).*To Private:\s+(\d+)\s+pods.*To Public:\s+(\d+)\s+pods'
    )
    
    try:
        with open(log_filepath, 'r') as f:
            for line in f:
                # Try new format first
                match = new_format_pattern.search(line)
                if not match:
                    # Fallback to old format
                    match = old_format_pattern.search(line)
                
                if match:
                    date_str = match.group(1)
                    execution_count = int(match.group(2))
                    label_type = match.group(3).strip()
                    total_migrated_pods = int(match.group(4))
                    migrated_to_private = int(match.group(5))
                    migrated_to_public = int(match.group(6))
                    
                    # Convert to Unix timestamp (seconds)
                    dt = datetime.strptime(date_str, '%Y/%m/%d %H:%M:%S')
                    timestamp = int(dt.timestamp())
                    
                    migrations.append({
                        'execution': execution_count,
                        'type': label_type,
                        'timestamp': timestamp,
                        'total_migrated_pods': total_migrated_pods,
                        'migrated_to_private': migrated_to_private,
                        'migrated_to_public': migrated_to_public
                    })
                    continue
                    
    except FileNotFoundError:
        print(f"Warning: Migration log file not found at {log_filepath}. Continuing without migration data.")
        return pd.DataFrame(columns=[
            'execution', 'type', 'timestamp', 'total_migrated_pods', 
            'migrated_to_private', 'migrated_to_public'
        ])
    
    if migrations:
        return pd.DataFrame(migrations)
    else:
        return pd.DataFrame(columns=[
            'execution', 'type', 'timestamp', 'total_migrated_pods', 
            'migrated_to_private', 'migrated_to_public'
        ])
