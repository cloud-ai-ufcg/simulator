import re
import pandas as pd

def parse_migration_logs(log_filepath):
    """Extrai o número de execução e os tipos de migração do log."""
    migrations = []
    with open(log_filepath, 'r') as f:
        for line in f:
            match = re.search(r'Label type: (.*), execution: (\d+)', line)
            if match:
                label_type = match.group(1).strip()
                execution_count = int(match.group(2))
                migrations.append({'execution': execution_count, 'type': label_type})
    return pd.DataFrame(migrations) if migrations else pd.DataFrame(columns=['execution', 'type'])
