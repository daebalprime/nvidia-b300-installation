#!/bin/bash
###############################################################################
# 99_downgrade_grafana_v11.sh [온라인 환경 전용]
#
# 역할:
#   1. 기존 실행 중인 모니터링 컨테이너 정지 및 리소스 정리
#   2. DB 스키마 충돌 방지를 위해 기존 마운트 폴더(/opt/monitoring/grafana-data 및 prometheus-data) 삭제
#   3. 신규 디렉토리 생성 및 올바른 권한(Prometheus 65534) 설정
#   4. 로컬 소스 설정 파일 및 docker-compose.yml(Grafana v11.5.2) 복사
#   5. 온라인 Docker Hub로부터 신규 Grafana v11.5.2 이미지 직접 Pull
#   6. 모니터링 스택 깨끗하게 재가동
###############################################################################
set -euo pipefail

MONITORING_DIR="/opt/monitoring"
TARGET_VERSION="11.5.2"

echo "=========================================================="
echo " Grafana Downgrade to v${TARGET_VERSION} & Data Purge (Online)"
echo "=========================================================="

# 0. 루트 권한 확인
if [ "$EUID" -ne 0 ]; then
    echo "  [ERROR] Please run this script with sudo."
    echo "  Usage: sudo $0"
    exit 1
fi

# ============================================================================
# Step 1: 기존 컨테이너 정지 및 삭제
# ============================================================================
echo ""
echo "[Step 1] Stopping active monitoring containers..."
if [ -f "${MONITORING_DIR}/docker-compose.yml" ]; then
    echo "  → Running docker compose down..."
    cd "${MONITORING_DIR}"
    docker compose down || true
else
    echo "  → ${MONITORING_DIR}/docker-compose.yml not found. Attempting generic docker stop..."
    docker stop prometheus grafana dcgm-exporter ipmi-exporter node-exporter 2>/dev/null || true
    docker rm prometheus grafana dcgm-exporter ipmi-exporter node-exporter 2>/dev/null || true
fi
echo "  [Complete] Container cleanup done"

# ============================================================================
# Step 2: 마운트 볼륨 폴더 데이터 완전히 초기화 (삭제)
# ============================================================================
echo ""
echo "[Step 2] Wiping mounted data folders to prevent DB version conflict..."

if [ -d "${MONITORING_DIR}/grafana-data" ]; then
    echo "  → Removing Grafana DB/data: ${MONITORING_DIR}/grafana-data"
    rm -rf "${MONITORING_DIR}/grafana-data"
fi

if [ -d "${MONITORING_DIR}/prometheus-data" ]; then
    echo "  → Removing Prometheus metrics: ${MONITORING_DIR}/prometheus-data"
    rm -rf "${MONITORING_DIR}/prometheus-data"
fi

echo "  [Complete] Data volumes successfully wiped!"

# ============================================================================
# Step 3: 새 디렉토리 생성 및 권한 설정
# ============================================================================
echo ""
echo "[Step 3] Re-creating clean data directories..."
mkdir -p "${MONITORING_DIR}"/{prometheus-data,grafana-data,config}

# 소유자 복구 (Prometheus 데이터 권한: 65534, 그 외: 현재 호출한 원 사용자 소유)
REAL_USER="${SUDO_USER:-$USER}"
chown -R "${REAL_USER}:${REAL_USER}" "${MONITORING_DIR}"
chown -R 65534:65534 "${MONITORING_DIR}/prometheus-data"
echo "  [Complete] Directories re-created with clean permissions"

# ============================================================================
# Step 4: 최신 설정(v11.5.2) 동기화 복사
# ============================================================================
echo ""
echo "[Step 4] Synchronizing docker-compose.yml and config files..."

# 스크립트 실행 경로 기준 설정 파일 위치 자동 탐색
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SEARCH_COMPOSE_PATHS=(
    "${SCRIPT_DIR}/monitoring/docker-compose.yml"
    "${SCRIPT_DIR}/../monitoring/docker-compose.yml"
    "${SCRIPT_DIR}/docker-compose.yml"
)

FOUND_COMPOSE=""
for COMPOSE_CANDIDATE in "${SEARCH_COMPOSE_PATHS[@]}"; do
    if [ -f "${COMPOSE_CANDIDATE}" ]; then
        FOUND_COMPOSE="${COMPOSE_CANDIDATE}"
        break
    fi
done

if [ -n "${FOUND_COMPOSE}" ]; then
    echo "  → Copying updated compose file from ${FOUND_COMPOSE}"
    cp "${FOUND_COMPOSE}" "${MONITORING_DIR}/docker-compose.yml"
    
    COMPOSE_DIR=$(dirname "${FOUND_COMPOSE}")
    if [ -d "${COMPOSE_DIR}/config" ]; then
        echo "  → Copying config directory templates to ${MONITORING_DIR}/config/"
        cp -r "${COMPOSE_DIR}/config"/* "${MONITORING_DIR}/config/" 2>/dev/null || true
    fi
    echo "  [Complete] Configurations copied successfully!"
else
    echo "  [WARNING] Could not find source docker-compose.yml."
    echo "  Please manually place the updated docker-compose.yml in ${MONITORING_DIR}/"
fi

# ============================================================================
# Step 5: 온라인 Docker Hub로부터 이미지 Pull
# ============================================================================
echo ""
echo "[Step 5] Pulling Grafana v${TARGET_VERSION} image from Docker Hub..."
docker pull "grafana/grafana:${TARGET_VERSION}"
echo "  [SUCCESS] Pulled Grafana v${TARGET_VERSION} image!"

# ============================================================================
# Step 6: 모니터링 스택 깨끗하게 가동
# ============================================================================
echo ""
echo "[Step 6] Launching clean Monitoring Stack..."
cd "${MONITORING_DIR}"

if [ -f "docker-compose.yml" ]; then
    echo "  → Running docker compose up -d..."
    docker compose up -d
    echo "  [Complete] Clean monitoring stack has been initialized."
else
    echo "  [ERROR] docker-compose.yml is missing in ${MONITORING_DIR}. Cannot start."
    exit 1
fi

# ============================================================================
# Step 7: 검증 및 출력
# ============================================================================
echo ""
echo "[Step 7] Verification..."
sleep 3
echo "--- Running containers ---"
docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}" | grep -E "grafana|prometheus" || true

echo ""
echo "=========================================================="
echo " Downgrade & Purge Task Complete!"
echo "=========================================================="
echo " - Grafana version downgraded to v${TARGET_VERSION} (Online)"
echo " - All old mount databases have been wiped and started fresh."
echo " - Grafana URL: http://$(hostname -I | awk '{print $1}'):3000"
echo "=========================================================="
