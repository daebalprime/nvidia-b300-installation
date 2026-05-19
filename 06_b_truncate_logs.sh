#!/bin/bash
###############################################################################
# 06_b_truncate_logs.sh
# [관리자 유틸리티] 모니터링 컴포즈 컨테이너 화면 로그(stdout) 일괄 비우기
#
# 역할:
#   - /opt/monitoring 에 기동 중인 모든 컨테이너의 도커 로그 경로를 자동 조회합니다.
#   - 서비스 중단(Restart) 없이 실시간으로 각 컨테이너의 로그 크기를 0으로 초기화합니다.
#   - 초기화 전/후의 로그 용량을 가시적으로 보고해 줍니다.
###############################################################################
set -euo pipefail

MONITORING_DIR="/opt/monitoring"

echo "=============================================="
echo " Monitoring Container Log Truncator"
echo "=============================================="

if [ ! -d "${MONITORING_DIR}" ]; then
    echo "  [ERROR] Monitoring directory (${MONITORING_DIR}) does not exist."
    exit 1
fi

cd "${MONITORING_DIR}"

# 1. 기동 중인 컨테이너 ID 추출 (node1 또는 node2 환경에 맞는 컴포즈 파일 자동 식별)
COMPOSE_FILE="docker-compose.yml"
if [ ! -f "docker-compose.yml" ] || sudo docker compose -f docker-compose.node2.yml ps -q &>/dev/null; then
    COMPOSE_FILE="docker-compose.node2.yml"
fi

echo "  Retrieving containers from ${COMPOSE_FILE}..."
CONTAINER_IDS=$(sudo docker compose -f "${COMPOSE_FILE}" ps -q 2>/dev/null || true)

if [ -z "${CONTAINER_IDS}" ]; then
    echo "  [WARN] No running monitoring containers found to truncate."
    exit 0
fi

# 2. 각 컨테이너별 로그 조회 및 실시간 Truncate 수행
echo "[Step 1] Truncating active container log files..."
echo "----------------------------------------------"

for CID in ${CONTAINER_IDS}; do
    # 컨테이너 실이름 및 로그 파일 절대 경로 획득
    CNAME=$(sudo docker inspect --format='{{.Name}}' "${CID}" | sed 's/^\///')
    LOG_PATH=$(sudo docker inspect --format='{{.LogPath}}' "${CID}" 2>/dev/null || true)

    if [ -n "${LOG_PATH}" ] && [ -f "${LOG_PATH}" ]; then
        # 초기화 전 용량 측정
        BEFORE_SIZE=$(sudo du -h "${LOG_PATH}" | awk '{print $1}')
        
        # 0바이트로 파일 크기만 절단 (실시간 리셋)
        sudo truncate -s 0 "${LOG_PATH}"
        
        echo "  [SUCCESS] ${CNAME} | Log Size: ${BEFORE_SIZE} -> 0B"
    else
        echo "  [SKIP] ${CNAME} | Log file not found or inactive."
    fi
done

echo "----------------------------------------------"
echo "=============================================="
echo " Log truncation completed successfully!"
echo "=============================================="
