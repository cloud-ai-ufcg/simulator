#!/bin/bash
# -----------------------------------------------------------------------------
# Update members.config to use Docker network IPs instead of localhost
# -----------------------------------------------------------------------------
set -euo pipefail

echo "🔧 Creating/updating members.config with Docker network IPs..."

MEMBER1_IP=$(docker inspect member1-control-plane 2>/dev/null | jq -r '.[0].NetworkSettings.Networks.kind.IPAddress' 2>/dev/null || echo "")
MEMBER2_IP=$(docker inspect member2-control-plane 2>/dev/null | jq -r '.[0].NetworkSettings.Networks.kind.IPAddress' 2>/dev/null || echo "")

if [ -z "$MEMBER1_IP" ] || [ -z "$MEMBER2_IP" ]; then
    echo "⚠️  Could not get cluster IPs"
    exit 1
fi

# Export kubeconfigs from kind
kind get kubeconfig --name member1 > /tmp/member1_temp.yaml
kind get kubeconfig --name member2 > /tmp/member2_temp.yaml

# Merge the configs and update IPs using Python
python3 <<PYTHON
import yaml
import sys

# Load member1 config
with open('/tmp/member1_temp.yaml', 'r') as f:
    member1_config = yaml.safe_load(f)

# Load member2 config  
with open('/tmp/member2_temp.yaml', 'r') as f:
    member2_config = yaml.safe_load(f)

# Start with member1 config as base
merged_config = member1_config.copy()

# Merge clusters from member2
for cluster in member2_config.get('clusters', []):
    merged_config['clusters'].append(cluster)

# Merge contexts from member2
for context in member2_config.get('contexts', []):
    merged_config['contexts'].append(context)

# Merge users from member2
for user in member2_config.get('users', []):
    merged_config['users'].append(user)

# Update IPs
for cluster in merged_config.get('clusters', []):
    if cluster['name'] == 'kind-member1':
        cluster['cluster']['server'] = f"https://${MEMBER1_IP}:6443"
    elif cluster['name'] == 'kind-member2':
        cluster['cluster']['server'] = f"https://${MEMBER2_IP}:6443"

# Rename contexts to simpler names
for context in merged_config.get('contexts', []):
    if context['name'] == 'kind-member1':
        context['name'] = 'member1'
    elif context['name'] == 'kind-member2':
        context['name'] = 'member2'

# Write the merged and updated config
with open('$HOME/.kube/members.config', 'w') as f:
    yaml.dump(merged_config, f, default_flow_style=False, sort_keys=False)

print("✅ Created members.config with updated endpoints")
PYTHON

echo "✅ members.config created/updated:"
echo "   member1: https://${MEMBER1_IP}:6443"
echo "   member2: https://${MEMBER2_IP}:6443"

# Cleanup temp files
rm /tmp/member1_temp.yaml /tmp/member2_temp.yaml

