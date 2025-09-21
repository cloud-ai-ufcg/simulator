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
    Expects lines like:
    - New format: 2025/09/20 15:30:45 📊 Migration Summary - Execution: 1 | Label type: public | Total migrated pods: 15 | To Private: 10 pods | To Public: 5 pods
    """
    migrations = []
    detailed_pattern = re.compile(
        r'^(\d{4}/\d{2}/\d{2} \d{2}:\d{2}:\d{2}).*📊 Migration Summary.*Execution: (\d+).*Label type: ([^|]+).*Total migrated pods: (\d+).*To Private: (\d+) pods.*To Public: (\d+) pods'
    )
    try:
        with open(log_filepath, 'r') as f:
            for line in f:
                detailed_match = detailed_pattern.search(line)
                if detailed_match:
                    date_str = detailed_match.group(1)
                    execution_count = int(detailed_match.group(2))
                    label_type = detailed_match.group(3).strip()
                    total_migrated_pods = int(detailed_match.group(4))
                    migrated_to_private = int(detailed_match.group(5))
                    migrated_to_public = int(detailed_match.group(6))
                    
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
