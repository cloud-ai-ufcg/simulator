import re
import pandas as pd

def parse_migration_logs(log_filepath):
    """Extrai timestamps e tipos de migração do log."""
    migrations = []
    with open(log_filepath, 'r') as f:
        for line in f:
            match = re.search(r'(\d{4}/\d{2}/\d{2} \d{2}:\d{2}:\d{2}).*Label type: (.*)', line)
            if match:
                timestamp_str = match.group(1)
                label_type = match.group(2).strip()
                dt_object = pd.to_datetime(timestamp_str, format='%Y/%m/%d %H:%M:%S')
                migrations.append({'timestamp': dt_object, 'type': label_type})
    return pd.DataFrame(migrations) if migrations else pd.DataFrame(columns=['timestamp', 'type'])
