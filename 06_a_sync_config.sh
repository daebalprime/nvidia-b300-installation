#!/bin/bash
###############################################################################
# 06_a_sync_config.sh
# [온라인/폐쇄망 공용] 설정 파일 및 컴포즈 파일 초고속 동기화 스크립트
#
# 역할:
#   - 매번 IP를 다시 입력할 필요 없이 기존에 적용되어 있던 Node 2 IP를 자동 탐지하여 복원합니다.
#   - 변경된 CSV/YAML 설정 파일과 docker-compose 파일을 /opt/monitoring/ 에 즉시 덮어씁니다.
#   - 현재 노드의 역할(node1 또는 node2)을 자동 감지하여 해당 서비스를 실시간 무중단 핫리로드 재생성합니다.
###############################################################################
set -euo pipefail

MONITORING_DIR="/opt/monitoring"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=============================================="
echo " Monitoring Config Sync & Hot-Reload"
echo "=============================================="

# 1. 원본 파일 위치 확인
SEARCH_PATHS=("${SCRIPT_DIR}/monitoring" "${SCRIPT_DIR}" "${SCRIPT_DIR}/.." "${SCRIPT_DIR}/../monitoring")
FOUND_SRC=""

for P in "${SEARCH_PATHS[@]}"; do
    if [ -f "${P}/docker-compose.node2.yml" ]; then
        FOUND_SRC="${P}"
        break
    fi
done

if [ -z "${FOUND_SRC}" ]; then
    echo "  [ERROR] Monitoring source directory not found."
    exit 1
fi

# 2. 기존 노드 역할(Role) 및 적용된 Node 2 IP 주소 자동 감지
NODE_ROLE="node2"
EXISTING_IP=""

# 현재 돌아가고 있는 도커 컨테이너 중 prometheus가 있으면 node1로 자동 판정
if sudo docker ps --format '{{.Names}}' | grep -q 'prometheus'; then
    NODE_ROLE="node1"
fi

# 기존 prometheus.yml 설정에서 기적용된 Node 2 IP 주소 추출
PROMETHEUS_TARGET="${MONITORING_DIR}/config/prometheus.yml"
if [ -f "${PROMETHEUS_TARGET}" ]; then
    # IPv4 정규식 패턴으로 매칭되는 기존 IP 주소 추출
    DETECTED_IP=$(grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' "${PROMETHEUS_TARGET}" | head -n 1 || true)
    if [ -n "${DETECTED_IP}" ] && [ "${DETECTED_IP}" != "127.0.0.1" ]; then
        EXISTING_IP="${DETECTED_IP}"
        echo "  [INFO] Detected existing Node 2 IP: ${EXISTING_IP}"
    fi
fi

# 3. 최신 설정 파일 동기화 복사
echo "[Step 1] Syncing configuration files..."
sudo mkdir -p "${MONITORING_DIR}/config"

# 일반 설정 파일 복사
if [ -d "${FOUND_SRC}/config" ]; then
    sudo cp -r "${FOUND_SRC}/config"/* "${MONITORING_DIR}/config/"
fi

# docker-compose 파일 복사
sudo cp "${FOUND_SRC}"/docker-compose*.yml "${MONITORING_DIR}/"

# 4. 추출한 기존 IP 자동 재적용 (Node 1인 경우)
if [ "${NODE_ROLE}" == "node1" ] && [ -n "${EXISTING_IP}" ]; then
    echo "[Step 2] Restoring existing Node 2 IP target (${EXISTING_IP}) to prometheus.yml..."
    sudo sed -i "s/hgx-node2:/${EXISTING_IP}:/g" "${MONITORING_DIR}/config/prometheus.yml"
fi

# 5. 무중단 핫리로드 재생성 실행
echo "[Step 3] Hot-reloading Docker Compose services (${NODE_ROLE})..."
cd "${MONITORING_DIR}"

if [ "${NODE_ROLE}" == "node1" ]; then
    sudo docker compose up -d --force-recreate
else
    sudo docker compose -f docker-compose.node2.yml up -d --force-recreate
fi

echo "=============================================="
echo " Sync & Hot-Reload complete! (Role: ${NODE_ROLE})"
echo "=============================================="
