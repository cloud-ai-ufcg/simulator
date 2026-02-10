#!/bin/bash
set -e 

KUBE_PATH="$HOME/.kube"
failed=0

check_prometheus_endpoint() {
    local url=$1
    local name=$2

    if ! command -v curl >/dev/null 2>&1; then
        echo -e "${RED}[FAIL] 'curl' is required to check Prometheus '$name' endpoint${NC}"
        failed=1
        return
    fi

    if curl --silent --fail --max-time 5 "$url" > /dev/null 2>&1; then
        echo -e "${GREEN}[OK] Prometheus '$name' is reachable at $url${NC}"
    else
        echo -e "${RED}[FAIL] Prometheus '$name' is NOT reachable at $url${NC}"
        failed=1
    fi
}

# Wait until the build.log file is generated
echo "Waiting for build.log to be generated..."
while [ ! -e "$KUBE_PATH/build.log" ]; do
    sleep 10
done

check_prometheus_endpoint "http://localhost:9090/-/ready" "member1"
check_prometheus_endpoint "http://localhost:9091/-/ready" "member2"

if [ $failed -eq 1 ]; then
    echo "A failed was detected in the infrastructure status checks. Please setup the environment again."
    exit 1
else 
    echo "Infrastructure status checks passed successfully."
    exit 0
fi

