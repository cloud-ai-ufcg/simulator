#!/bin/bash

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

failed=0

check_command() {
    if ! command -v "$1" &> /dev/null; then
        echo -e "${RED}[FAIL] Command '$1' not found${NC}"
        failed=1
    else
        echo -e "${GREEN}[OK] Command '$1' found${NC}"
    fi
}

check_container() {
    if docker ps --format '{{.Names}}' | grep -q "^$1$"; then
        echo -e "${GREEN}[OK] Container '$1' is running${NC}"
    else
        echo -e "${RED}[FAIL] Container '$1' is NOT running${NC}"
        failed=1
    fi
}

check_file() {
    if [ -f "$1" ]; then
        echo -e "${GREEN}[OK] File '$1' exists${NC}"
    else
        echo -e "${RED}[FAIL] File '$1' not found${NC}"
        failed=1
    fi
}

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

echo "========================================"
echo "Verifying environment for 'make start'"
echo "========================================"

# 1. Check Required Tools
echo -e "\n[Checking Required Tools]"
check_command go
check_command docker

# 2. Check Kubernetes Infrastructure (Kind Clusters)
echo -e "\n[Checking Kubernetes Infrastructure]"
check_container karmada-host-control-plane
check_container member1-control-plane
check_container member2-control-plane

# 3. Check Docker Compose Services
echo -e "\n[Checking Services]"
check_container broker
check_container monitor
check_container ai-engine
check_container actuator
check_container mongo

 # 4. Check Simulator Code
 echo -e "\n[Checking Simulator Code]"
 check_file "simulator/cmd/main.go"
 
 echo -e "\n[Checking Prometheus Endpoints]"
 check_prometheus_endpoint "http://localhost:9090/-/ready" "member1"
 check_prometheus_endpoint "http://localhost:9091/-/ready" "member2"
 
 echo "========================================"
 if [ $failed -eq 0 ]; then
     echo -e "${GREEN}Everything looks ready for 'make start'!${NC}"
    exit 0
else
    echo -e "${RED}Some requirements are missing. Please fix them before running 'make start'.${NC}"
    exit 1
fi
