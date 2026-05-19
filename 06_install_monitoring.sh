#!/bin/bash
###############################################################################
# 06_install_monitoring.sh
# [온라인 환경용] 모니터링 스택 설치 (Prometheus + Exporters)
#
# 사용법:
#   ./06_install_monitoring.sh node1    # Node 1: Prometheus + 모든 Exporter
#   ./06_install_monitoring.sh node2    # Node 2: Exporter만 실행
###############################################################################
set -euo pipefail

NODE_ROLE="${1:-}"
MONITORING_DIR="/opt/monitoring"

# 설정 파일 위치 (프로젝트 내 monitoring 폴더)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MONITORING_SRC="${SCRIPT_DIR}/../monitoring"

echo "=============================================="
echo " Monitoring Stack Installation (Online Mode)"
echo "=============================================="

# 1. 노드 역할 선택
if [ -z "${NODE_ROLE}" ]; then
    echo "  Select this server's role:"
    echo "    1) node1 - Prometheus + All Exporters"
    echo "    2) node2 - Exporters Only"
    read -p "  Choice (1 or 2): " CHOICE
    case "${CHOICE}" in
        1) NODE_ROLE="node1" ;;
        2) NODE_ROLE="node2" ;;
        *) echo "  [ERROR] Invalid choice."; exit 1 ;;
    esac
fi

# 2. 필수 패키지 설치 (IPMI 도구 등)
echo "[Step 2] Installing dependency packages..."
sudo apt-get install -y freeipmi-tools ipmitool

# 3. 디렉토리 및 설정 파일 준비
echo "[Step 3] Preparing directories..."
sudo mkdir -p ${MONITORING_DIR}/{prometheus-data,config}

# 파일 찾기 (여러 후보 경로 탐색)
SEARCH_PATHS=("${SCRIPT_DIR}/monitoring" "${SCRIPT_DIR}" "${SCRIPT_DIR}/.." "${SCRIPT_DIR}/../monitoring")
FOUND_SRC=""

for P in "${SEARCH_PATHS[@]}"; do
    if [ -f "${P}/docker-compose.node2.yml" ]; then
        FOUND_SRC="${P}"
        break
    fi
done

if [ -n "${FOUND_SRC}" ]; then
    echo "  Found monitoring files in ${FOUND_SRC}"
    # 설정 파일들 복사
    [ -d "${FOUND_SRC}/config" ] && sudo cp -r "${FOUND_SRC}/config"/* "${MONITORING_DIR}/config/" 2>/dev/null || true
    # docker-compose 파일들 복사
    sudo cp "${FOUND_SRC}"/docker-compose*.yml "${MONITORING_DIR}/"
else
    echo "  [ERROR] Cannot find docker-compose.node2.yml in search paths."
    exit 1
fi

# 4. Docker Compose 실행
echo "[Step 4] Starting Monitoring Stack via Docker Compose..."
cd ${MONITORING_DIR}

if [ "${NODE_ROLE}" == "node1" ]; then
    read -p "  Enter Node 2's IP address: " NODE2_IP
    # Prometheus 설정 파일 수정
    if [ -f "config/prometheus.yml" ]; then
        sudo sed -i "s/hgx-node2/${NODE2_IP}/g" config/prometheus.yml
    fi
    sudo docker compose up -d
else
    sudo docker compose -f docker-compose.node2.yml up -d
fi

# 5. 검증
echo "[Step 5] Verification..."
sleep 5
curl -sf http://localhost:9400/metrics | head -n 1 && echo "  [PASS] DCGM Exporter is running" || echo "  [FAIL] DCGM Exporter check failed"
curl -sf http://localhost:9100/metrics | head -n 1 && echo "  [PASS] Node Exporter is running" || echo "  [FAIL] Node Exporter check failed"
curl -sf http://localhost:9290/metrics | head -n 1 && echo "  [PASS] IPMI Exporter is running" || echo "  [FAIL] IPMI Exporter check failed"

echo "=============================================="
echo " Monitoring installation complete! (${NODE_ROLE})"
echo "=============================================="
