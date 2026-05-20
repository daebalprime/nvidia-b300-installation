#!/bin/bash
###############################################################################
# 06_d_verify_metrics.sh
# [모니터링 실시간 메트릭 검증 도구]
#
# 역할:
#   - Exporter들로부터 실제 수집 중인 실시간 원시 메트릭(Raw Metrics)을 직접 파싱
#   - 주요 수집 값(CPU, MEM, GPU 온도/전력/메모리/사용률, IPMI 팬/온도/전력)을 가시화 출력
#   - Node 1의 경우 Prometheus Target API를 조회하여 각 Exporter 수집 상태 최종 검증
###############################################################################
set -euo pipefail

# ANSI 컬러 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

echo -e "${BLUE}======================================================================${NC}"
echo -e "${BLUE}        HGX B300 MoC - Real-time Metrics Verification Utility        ${NC}"
echo -e "${BLUE}======================================================================${NC}"

# 1. 노드 역할 자동 판정
NODE_ROLE="node2"
if sudo docker ps --format '{{.Names}}' | grep -q 'prometheus'; then
    NODE_ROLE="node1"
elif [ -f "/opt/monitoring/docker-compose.yml" ] && ! [ -f "/opt/monitoring/docker-compose.node2.yml" ]; then
    NODE_ROLE="node1"
fi

echo -e "  [INFO] Detected Role: ${YELLOW}${NODE_ROLE}${NC}"
echo -e "${BLUE}----------------------------------------------------------------------${NC}"

# 유틸리티 함수: 단위 변환 및 값 포맷팅
format_bytes_to_gb() {
    local BYTES=$1
    echo | awk -v b="$BYTES" '{printf "%.2f GB", b / 1024 / 1024 / 1024}'
}

# ======================================================================
# [Step 1] Node Exporter (OS) 메트릭 추출
# ======================================================================
echo -e "\n${CYAN}[1/3] OS METRICS (Node Exporter - Port 9100)${NC}"
if curl -sf -m 3 http://localhost:9100/metrics > /tmp/node_metrics.tmp 2>/dev/null; then
    # Load Average
    LOAD1=$(grep -E '^node_load1 ' /tmp/node_metrics.tmp | awk '{print $2}')
    LOAD5=$(grep -E '^node_load5 ' /tmp/node_metrics.tmp | awk '{print $2}')
    LOAD15=$(grep -E '^node_load15 ' /tmp/node_metrics.tmp | awk '{print $2}')
    
    # Memory Info
    MEM_TOTAL=$(grep -E '^node_memory_MemTotal_bytes ' /tmp/node_metrics.tmp | awk '{print $2}')
    MEM_AVAIL=$(grep -E '^node_memory_MemAvailable_bytes ' /tmp/node_metrics.tmp | awk '{print $2}')
    MEM_USED=$(echo | awk -v t="$MEM_TOTAL" -v a="$MEM_AVAIL" '{print t - a}')
    MEM_PERC=$(echo | awk -v u="$MEM_USED" -v t="$MEM_TOTAL" '{printf "%.1f", (u / t) * 100}')
    
    # Disk Usage (Root filesystem /)
    DISK_SIZE=$(grep -E '^node_filesystem_size_bytes\{device=.*,fstype=.*,mountpoint="/"\}' /tmp/node_metrics.tmp | awk '{print $2}')
    DISK_FREE=$(grep -E '^node_filesystem_free_bytes\{device=.*,fstype=.*,mountpoint="/"\}' /tmp/node_metrics.tmp | awk '{print $2}')
    if [ -n "${DISK_SIZE}" ] && [ -n "${DISK_FREE}" ]; then
        DISK_USED=$(echo | awk -v s="$DISK_SIZE" -v f="$DISK_FREE" '{print s - f}')
        DISK_PERC=$(echo | awk -v u="$DISK_USED" -v s="$DISK_SIZE" '{printf "%.1f", (u / s) * 100}')
        DISK_STR="$(format_bytes_to_gb "$DISK_USED") / $(format_bytes_to_gb "$DISK_SIZE") (${DISK_PERC}%)"
    else
        DISK_STR="N/A"
    fi

    echo -e "  - ${GREEN}CPU Load Average${NC} : 1m: ${YELLOW}${LOAD1}${NC} | 5m: ${YELLOW}${LOAD5}${NC} | 15m: ${YELLOW}${LOAD15}${NC}"
    echo -e "  - ${GREEN}Physical Memory${NC}  : $(format_bytes_to_gb "$MEM_USED") / $(format_bytes_to_gb "$MEM_TOTAL") (${YELLOW}${MEM_PERC}% used${NC})"
    echo -e "  - ${GREEN}Disk Space (/)${NC}   : ${DISK_STR}"
    
    # InfiniBand Active check
    IB_PORTS=$(grep -cE '^node_infiniband_port_data_received_bytes_total' /tmp/node_metrics.tmp || true)
    if [ "$IB_PORTS" -gt 0 ]; then
        echo -e "  - ${GREEN}InfiniBand Ports${NC} : ${YELLOW}${IB_PORTS} active ports${NC} monitored via Node Exporter."
    else
        echo -e "  - ${GREEN}InfiniBand Ports${NC} : ${RED}None detected${NC} (Check driver or network stack)."
    fi
else
    echo -e "  - [${RED}FAIL${NC}] Node Exporter is unreachable on http://localhost:9100/metrics"
fi

# ======================================================================
# [Step 2] DCGM Exporter (GPU) 메트릭 추출
# ======================================================================
echo -e "\n${CYAN}[2/3] GPU METRICS (DCGM Exporter - Port 9400)${NC}"
if curl -sf -m 3 http://localhost:9400/metrics > /tmp/dcgm_metrics.tmp 2>/dev/null; then
    # GPU 개수 판단 (DCGM_FI_DEV_GPU_TEMP 항목 기준)
    GPUS=$(grep -E '^DCGM_FI_DEV_GPU_TEMP' /tmp/dcgm_metrics.tmp | awk -F'[{,]' '{
        for(i=1;i<=NF;i++) {
            if($i ~ /^gpu=/) {
                print $i
            }
        }
    }' | sed 's/gpu="//;s/"//' | sort -n -u)
    
    if [ -z "${GPUS}" ]; then
        echo -e "  - [${YELLOW}WARN${NC}] DCGM Exporter reachable but returned no active GPUs."
    else
        echo -e "  +-----+-------------------------+-------------+-------------+------------------+-----------------+"
        echo -e "  | ${MAGENTA}GPU${NC} | ${MAGENTA}UUID                      ${NC} | ${MAGENTA}Temperature${NC} | ${MAGENTA}Power Usage${NC} | ${MAGENTA}FB Memory (Used)${NC} | ${MAGENTA}GPU Utilization${NC} |"
        echo -e "  +-----+-------------------------+-------------+-------------+------------------+-----------------+"
        
        for G in ${GPUS}; do
            # UUID 추출
            UUID=$(grep -E "^DCGM_FI_DEV_GPU_TEMP" /tmp/dcgm_metrics.tmp | grep "gpu=\"$G\"" | grep -oE "UUID=\"[^\"]+\"" | head -n 1 | sed 's/UUID="//;s/"//' | cut -c1-23 || true)
            [ -z "${UUID}" ] && UUID="N/A"
            
            # 메트릭들 파싱
            TEMP=$(grep -E "^DCGM_FI_DEV_GPU_TEMP\{.*gpu=\"$G\".*\}" /tmp/dcgm_metrics.tmp | awk '{print $2}')
            POWER=$(grep -E "^DCGM_FI_DEV_POWER_USAGE\{.*gpu=\"$G\".*\}" /tmp/dcgm_metrics.tmp | awk '{print $2}')
            FB_USED=$(grep -E "^DCGM_FI_DEV_FB_USED\{.*gpu=\"$G\".*\}" /tmp/dcgm_metrics.tmp | awk '{print $2}')
            FB_TOTAL=$(grep -E "^DCGM_FI_DEV_FB_TOTAL\{.*gpu=\"$G\".*\}" /tmp/dcgm_metrics.tmp | awk '{print $2}')
            UTIL=$(grep -E "^DCGM_FI_DEV_GPU_UTIL\{.*gpu=\"$G\".*\}" /tmp/dcgm_metrics.tmp | awk '{print $2}')
            
            # 기본값 보정
            [ -z "${TEMP}" ] && TEMP="N/A" || TEMP="${TEMP}°C"
            [ -z "${POWER}" ] && POWER="N/A" || POWER="${POWER} W"
            if [ -n "${FB_USED}" ] && [ -n "${FB_TOTAL}" ]; then
                FB_STR="${FB_USED} / ${FB_TOTAL} MiB"
            else
                FB_STR="N/A"
            fi
            [ -z "${UTIL}" ] && UTIL="N/A" || UTIL="${UTIL}%"
            
            printf "  | %-3s | %-23s | %-11s | %-11s | %-16s | %-15s |\n" "${G}" "${UUID}" "${TEMP}" "${POWER}" "${FB_STR}" "${UTIL}"
        done
        echo -e "  +-----+-------------------------+-------------+-------------+------------------+-----------------+"
        
        # NVLink 에러 유무 진단
        CRC_ERRS=$(grep -E '^DCGM_FI_DEV_NVLINK_CRC_DATA_ERROR_COUNT_TOTAL' /tmp/dcgm_metrics.tmp | awk '{sum+=$2} END {print sum}' || true)
        REPLAY_ERRS=$(grep -E '^DCGM_FI_DEV_NVLINK_REPLAY_ERROR_COUNT_TOTAL' /tmp/dcgm_metrics.tmp | awk '{sum+=$2} END {print sum}' || true)
        
        if [ -n "${CRC_ERRS}" ] && [ "${CRC_ERRS}" != "0" ]; then
            echo -e "  - ${RED}[ALERT] NVLink Data CRC Errors detected: ${CRC_ERRS}${NC}"
        else
            echo -e "  - ${GREEN}NVLink Fabric${NC} : Healthy (0 CRC Data Errors)"
        fi
    fi
else
    echo -e "  - [${RED}FAIL${NC}] DCGM Exporter is unreachable on http://localhost:9400/metrics"
fi

# ======================================================================
# [Step 3] IPMI Exporter (Chassis) 메트릭 추출
# ======================================================================
echo -e "\n${CYAN}[3/3] HARDWARE METRICS (IPMI Exporter - Port 9290)${NC}"
# IPMI는 로컬 BMC 접근을 위해 target=127.0.0.1 및 module=default 파라미터 필요
if curl -sf -m 5 "http://localhost:9290/ipmi?module=default&target=127.0.0.1" > /tmp/ipmi_metrics.tmp 2>/dev/null; then
    # 핵심 하드웨어 상태 필터링 출력
    echo -e "  ${YELLOW}System IPMI Sensors Status:${NC}"
    
    # 1. 시스템 총 전력 소비 (DCMI 메트릭 우선 검색)
    SYS_POWER=$(grep -iE '^ipmi_sensor_value\{.*name=".*Power.*"\}' /tmp/ipmi_metrics.tmp | grep -iE 'watts|w' | head -n 2 || true)
    if [ -n "${SYS_POWER}" ]; then
        echo "${SYS_POWER}" | while read -r line; do
            NAME=$(echo "$line" | sed 's/.*name="//;s/".*//')
            VAL=$(echo "$line" | awk '{print $2}')
            echo -e "    - ${GREEN}${NAME}${NC} : ${YELLOW}${VAL} W${NC}"
        done
    else
        echo -e "    - ${GREEN}System Power Draw${NC} : Not exported or no direct matching sensor."
    fi
    
    # 2. 메인 팬 속도 (RPM 리스트 요약)
    FAN_SENSORS=$(grep -iE '^ipmi_sensor_value\{.*name=".*Fan.*"\}' /tmp/ipmi_metrics.tmp | head -n 4 || true)
    if [ -n "${FAN_SENSORS}" ]; then
        echo -e "    - ${GREEN}System Fans (Top 4)${NC} :"
        echo "${FAN_SENSORS}" | while read -r line; do
            NAME=$(echo "$line" | sed 's/.*name="//;s/".*//')
            VAL=$(echo "$line" | awk '{print $2}')
            echo -e "      * ${NAME} : ${YELLOW}${VAL} RPM${NC}"
        done
    else
        echo -e "    - ${GREEN}System Fans Speed${NC} : N/A"
    fi
    
    # 3. 섀시 전반적인 위기 플래그 감지
    CRIT_FLAGS=$(grep -iE '^ipmi_sensor_state\{.*state="critical"\}' /tmp/ipmi_metrics.tmp | awk '{sum+=$2} END {print sum}' || true)
    if [ -n "${CRIT_FLAGS}" ] && [ "${CRIT_FLAGS}" != "0" ] && [ "${CRIT_FLAGS}" != "NaN" ]; then
        echo -e "    - ${RED}[WARNING] IPMI detected ${CRIT_FLAGS} critical hardware state alarms!${NC}"
    else
        echo -e "    - ${GREEN}Hardware Diagnostics${NC} : Healthy (0 critical sensor alarms)"
    fi
else
    echo -e "  - [${RED}FAIL${NC}] IPMI Exporter is unreachable on http://localhost:9290/ipmi"
    echo -e "           (Check if local BMC interface /dev/ipmi0 is accessible and driver loaded)"
fi

# ======================================================================
# [Step 4] Prometheus 타겟 헬스 점검 (Node 1 전용)
# ======================================================================
if [ "${NODE_ROLE}" == "node1" ]; then
    echo -e "\n${CYAN}[4/4] PROMETHEUS SCRAPING ENDPOINTS HEALTH (Prometheus - Port 9090)${NC}"
    if curl -sf -m 3 http://localhost:9090/api/v1/targets > /tmp/prometheus_targets.tmp 2>/dev/null; then
        # 파이썬을 이용한 JSON 간편 정렬 출력
        python3 -c '
import json, sys
try:
    with open("/tmp/prometheus_targets.tmp") as f:
        data = json.load(f)
    active_targets = data.get("data", {}).get("activeTargets", [])
    print(f"  Scrape Target Status Overview ({len(active_targets)} targets registered):")
    for t in active_targets:
        job = t.get("labels", {}).get("job", "unknown")
        inst = t.get("labels", {}).get("instance", "unknown")
        health = t.get("health", "unknown")
        url = t.get("scrapeUrl", "")
        
        # Color coding
        h_color = "\033[0;32mUP\033[0m" if health == "up" else f"\033[0;31m{health.upper()}\033[0m"
        print(f"    - Job: {job:<15} | Inst: {inst:<12} | Status: {h_color} | URL: {url}")
except Exception as e:
    print("    [ERROR] Failed to parse Prometheus targets JSON:", e)
' || echo "  - [WARN] Python parsing failed."
    else
        echo -e "  - [${RED}FAIL${NC}] Prometheus Server is unreachable on http://localhost:9090"
    fi
fi

# 임시 파일 소거
rm -f /tmp/node_metrics.tmp /tmp/dcgm_metrics.tmp /tmp/ipmi_metrics.tmp /tmp/prometheus_targets.tmp 2>/dev/null || true

echo -e "\n${BLUE}======================================================================${NC}"
echo -e "${GREEN}             Metrics Verification Completed Successfully!            ${NC}"
echo -e "${BLUE}======================================================================${NC}"
