#!/bin/bash
###############################################################################
# 06_c_check_monitoring_state.sh
# [자가 진단 유틸리티] 모니터링 스택 전체 기동 및 헬스 체크 진단 도구
#
# 역할:
#   - 노드 역할(node1 / node2) 자동 감지
#   - 컴포즈 컨테이너들의 실시간 기동 상태(Up, Exited 등) 및 하드웨어 사용량 출력
#   - Exporter별 포트 개방 상태 및 HTTP 메트릭 응답 무결성 진단
#   - 컨테이너별 최근 에러 로그(ERROR, panic, Exception 등) 자동 스캔 보고
###############################################################################
set -euo pipefail

MONITORING_DIR="/opt/monitoring"

# ANSI 컬러 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}======================================================${NC}"
echo -e "${BLUE}       Monitoring Stack Diagnostics & Health Check    ${NC}"
echo -e "${BLUE}======================================================${NC}"

if [ ! -d "${MONITORING_DIR}" ]; then
    echo -e "  [${RED}ERROR${NC}] Monitoring directory (${MONITORING_DIR}) does not exist."
    exit 1
fi

cd "${MONITORING_DIR}"

# 1. 노드 역할 자동 판정
NODE_ROLE="node2"
COMPOSE_FILE="docker-compose.node2.yml"

if sudo docker ps --format '{{.Names}}' | grep -q 'prometheus'; then
    NODE_ROLE="node1"
    COMPOSE_FILE="docker-compose.yml"
elif [ -f "docker-compose.yml" ] && ! [ -f "docker-compose.node2.yml" ]; then
    NODE_ROLE="node1"
    COMPOSE_FILE="docker-compose.yml"
fi

echo -e "  [INFO] Detected Server Role: ${YELLOW}${NODE_ROLE}${NC} (Using ${COMPOSE_FILE})"
echo -e "${BLUE}------------------------------------------------------${NC}"

# 2. 컨테이너 기동 상태 및 생존 체크
echo -e "\n${BLUE}[Step 1] Container Status Summary:${NC}"
CONTAINER_IDS=$(sudo docker compose -f "${COMPOSE_FILE}" ps -q 2>/dev/null || true)

if [ -z "${CONTAINER_IDS}" ]; then
    echo -e "  [${RED}WARNING${NC}] No running containers found for this stack."
else
    # 컨테이너 정보 상세 출력
    sudo docker compose -f "${COMPOSE_FILE}" ps --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}"
    
    echo -e "\n${BLUE}[Resource Utilization (CPU / MEM / Net I/O)]:${NC}"
    # 각 컨테이너 리소스 조회
    sudo docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}" ${CONTAINER_IDS}
fi

# 3. 네트워크 포트 및 HTTP 메트릭 검증
echo -e "\n${BLUE}[Step 2] Port & HTTP Metric Endpoint Verification:${NC}"

verify_endpoint() {
    local NAME=$1
    local PORT=$2
    local PATH_URI=$3
    
    echo -n "  Checking ${NAME} (Port ${PORT})... "
    
    # 1단계: 포트 리스닝 검증 (ss 또는 netstat 대용으로 curl 커넥션 제한 시도)
    if curl -s -m 2 "http://localhost:${PORT}${PATH_URI}" &>/dev/null; then
        # 2단계: 메트릭 내용 검증 (헤더 분석)
        local HEADER
        HEADER=$(curl -sf -m 2 "http://localhost:${PORT}${PATH_URI}" | head -n 1 || true)
        if [ -n "${HEADER}" ]; then
            echo -e "[${GREEN}PASS${NC}] (Response: '${HEADER}')"
        else
            echo -e "[${YELLOW}WARN${NC}] Port is listening but returned empty response."
        fi
    else
        echo -e "[${RED}FAIL${NC}] Port is unreachable (Container might be dead or AppArmor-blocked)."
    fi
}

verify_endpoint "Node Exporter" "9100" "/metrics"
verify_endpoint "DCGM Exporter" "9400" "/metrics"
verify_endpoint "IPMI Exporter" "9290" "/metrics"

if [ "${NODE_ROLE}" == "node1" ]; then
    verify_endpoint "Prometheus Server" "9090" "/-/healthy"
fi

# 4. 실시간 위험 로그 검출 (ERROR / FATAL / panic 스캔)
echo -e "\n${BLUE}[Step 3] Target Service Log Scan (Last 10 lines):${NC}"

for CID in ${CONTAINER_IDS}; do
    CNAME=$(sudo docker inspect --format='{{.Name}}' "${CID}" | sed 's/^\///')
    echo -e "\n  Analyzing logs for: ${YELLOW}${CNAME}${NC}..."
    
    # 최근 10줄 로그 확보
    LOG_TAIL=$(sudo docker logs --tail 10 "${CID}" 2>&1 || true)
    
    # 에러 키워드 하이라이팅 매칭
    if echo "${LOG_TAIL}" | grep -qE -i "error|fatal|panic|failed|denied|exception"; then
        echo -e "  [${RED}ALERT${NC}] Potential issues detected in logs:"
        # 에러 관련 키워드만 빨갛게 칠해서 출력
        echo "${LOG_TAIL}" | grep --color=always -E -i "error|fatal|panic|failed|denied|exception|.*" || true
    else
        echo -e "  [${GREEN}HEALTHY${NC}] No error patterns found in recent logs."
        # 일반 출력 (앞부분만 간략하게)
        echo "${LOG_TAIL}" | head -n 3 | sed 's/^/    /' || true
        echo "    ..."
    fi
done

echo -e "\n${BLUE}======================================================${NC}"
echo -e "${GREEN}             Diagnostic Check Complete!               ${NC}"
echo -e "${BLUE}======================================================${NC}"
