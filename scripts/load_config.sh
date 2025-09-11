CONFIG_FILE=$1

set -a 
# Infrastructure variables
MEMBER1_NODES=$(yq '.clusters.member1.nodes' "$CONFIG_FILE")
MEMBER1_CPU=$(yq '.clusters.member1.cpu' "$CONFIG_FILE")
MEMBER1_MEM=$(yq '.clusters.member1.memory' "$CONFIG_FILE")
MEMBER2_NODES=$(yq '.clusters.member2.nodes' "$CONFIG_FILE")
MEMBER2_CPU=$(yq '.clusters.member2.cpu' "$CONFIG_FILE")
MEMBER2_MEM=$(yq '.clusters.member2.memory' "$CONFIG_FILE")
MEMBER2_AUTOSCALER=$(yq '.clusters.member2.autoscaler' "$CONFIG_FILE")

PROMETHEUS_GRAFANA_ENABLE=$(yq '.prometheus.grafana_enable' "$CONFIG_FILE")

# AI-engine variables 
SCHEDULER_INTERVAL=$(yq '.ai-engine.scheduler_interval' "$CONFIG_FILE")
TIMESTAMP_LOOKBACK_SECONDS=$(yq '.ai-engine.timestamp_lookback_seconds' "$CONFIG_FILE")
WORKLOADS_SHARD_SIZE=$(yq '.ai-engine.workload_shard_size' "$CONFIG_FILE")
MONITORED_DURATION_SEC=$(yq '.ai-engine.monitored_duration_sec' "$CONFIG_FILE")

# Monitor variables
COLLECTION_INTERVAL=$(yq '.monitor.collection_interval' "$CONFIG_FILE")
set +a