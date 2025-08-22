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
    Extracts the migration type and time from the log, converting it to a Unix timestamp.
    Expects lines like:
    2025/08/20 18:07:40 Label type: private, execution: 1
    """
    migrations = []
    pattern = re.compile(r'^(\d{4}/\d{2}/\d{2} \d{2}:\d{2}:\d{2}).*Label type: (.*), execution: (\d+)')
    try:
        with open(log_filepath, 'r') as f:
            for line in f:
                match = pattern.search(line)
                if match:
                    date_str = match.group(1)
                    label_type = match.group(2).strip()
                    execution_count = int(match.group(3))
                    # Convert to Unix timestamp (seconds)
                    dt = datetime.strptime(date_str, '%Y/%m/%d %H:%M:%S')
                    timestamp = int(dt.timestamp())
                    migrations.append({'execution': execution_count, 'type': label_type, 'timestamp': timestamp})
    except FileNotFoundError:
        print(f"Warning: Migration log file not found at {log_filepath}. Continuing without migration data.")
        return pd.DataFrame(columns=['execution', 'type', 'timestamp'])
    
    return pd.DataFrame(migrations) if migrations else pd.DataFrame(columns=['execution', 'type', 'timestamp'])
