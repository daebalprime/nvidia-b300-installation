#!/bin/bash
###############################################################################
# 09_dump_prometheus.sh
# [HGX B300 모니터링 - 프로메테우스 메트릭 덤프 도구]
#
# 역할:
#   - Prometheus TSDB Admin API를 통해 실시간 데이터베이스 스냅샷을 생성합니다.
#   - 생성된 스냅샷을 지정한 백업 경로(USB, SSD 또는 로컬 디렉토리)로 안전하게 복사합니다.
#   - 스냅샷 생성 후 서버 내 원본 임시 스냅샷 파일을 옵션에 따라 자동으로 정리합니다.
#
# 사용법:
#   ./09_dump_prometheus.sh                  # 스냅샷만 서버 내에 생성
#   ./09_dump_prometheus.sh /mnt/usb         # 스냅샷 생성 + 지정 경로로 복사 (없으면 자동 생성)
#   ./09_dump_prometheus.sh /mnt/usb clean   # 복사 완료 후 서버 내의 스냅샷 데이터 정리
###############################################################################
set -euo pipefail

# ANSI 컬러 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

PROMETHEUS_URL="http://localhost:9090"
PROMETHEUS_DATA="/opt/monitoring/prometheus-data"
EXPORT_PATH="${1:-}"
CLEAN_AFTER="${2:-}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

echo -e "${BLUE}======================================================================${NC}"
echo -e "${BLUE}             Prometheus TSDB Metrics Dump Utility                     ${NC}"
echo -e "${BLUE}======================================================================${NC}"

# ============================================================================
# 사전 검증: Prometheus 컨테이너 구동 여부 및 노드 역할 판별
# ============================================================================
echo -e "\n${CYAN}[Step 1] Verifying local Prometheus status...${NC}"

# 도커 및 prometheus 컨테이너 기동 판별
if ! sudo docker ps --format '{{.Names}}' | grep -q 'prometheus'; then
    echo -e "  [${RED}ERROR${NC}] Prometheus 컨테이너가 이 서버에서 실행 중이지 않습니다."
    echo -e "          본 PoC 아키텍처에서 Prometheus 서버는 ${YELLOW}Node 1${NC}에서만 구동됩니다."
    echo -e "          현재 서버가 Node 2인 경우, Node 1 서버로 접속하여 본 스크립트를 실행해 주세요."
    exit 1
fi

# Prometheus 헬스체크 API 호출
if ! curl -sf "${PROMETHEUS_URL}/-/healthy" > /dev/null 2>&1; then
    echo -e "  [${RED}ERROR${NC}] Prometheus 서버가 응답하지 않습니다: ${PROMETHEUS_URL}"
    echo -e "          컨테이너 상태 및 포트 맵핑(9090)을 다시 확인해 주세요."
    exit 1
fi

echo -e "  - [${GREEN}OK${NC}] Prometheus is running healthy."

# 현재 TSDB 저장 용량 확인
echo -e "  - Current Local TSDB Size:"
if [ -d "${PROMETHEUS_DATA}" ]; then
    sudo du -sh "${PROMETHEUS_DATA}" 2>/dev/null | awk '{print "    → Size: " $1}' || echo "    → (Unable to read size)"
else
    echo -e "    → [${YELLOW}WARN${NC}] Prometheus data directory (${PROMETHEUS_DATA}) not found."
fi

# ============================================================================
# Step 2: TSDB 스냅샷 생성 API 호출
# ============================================================================
echo -e "\n${CYAN}[Step 2] Triggering TSDB snapshot creation...${NC}"
echo -e "  - Requesting snapshot via Admin API..."

# Admin API curl 호출
if ! RESPONSE=$(curl -sf -XPOST "${PROMETHEUS_URL}/api/v1/admin/tsdb/snapshot" 2>/dev/null); then
    echo -e "  [${RED}ERROR${NC}] 스냅샷 생성 요청이 실패했습니다."
    echo -e "          Prometheus 구동 옵션에 ${YELLOW}--web.enable-admin-api${NC}가 켜져 있는지 확인해 주세요."
    exit 1
fi

# POSIX-compliant sed 파싱으로 안전하게 name 속성 추출 (공백 유무와 상관없음)
SNAPSHOT_NAME=$(echo "${RESPONSE}" | sed -n 's/.*"name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')

if [ -z "${SNAPSHOT_NAME}" ]; then
    echo -e "  [${RED}ERROR${NC}] 응답 본문에서 스냅샷 식별자(name)를 찾을 수 없습니다."
    echo -e "          API 응답 내용: ${RESPONSE}"
    exit 1
fi

SNAPSHOT_DIR="${PROMETHEUS_DATA}/snapshots/${SNAPSHOT_NAME}"
echo -e "  - [${GREEN}SUCCESS${NC}] TSDB Snapshot Created!"
echo -e "  - Snapshot ID  : ${YELLOW}${SNAPSHOT_NAME}${NC}"
echo -e "  - Snapshot Path: ${YELLOW}${SNAPSHOT_DIR}${NC}"

# 스냅샷 크기 확인
if [ -d "${SNAPSHOT_DIR}" ]; then
    sudo du -sh "${SNAPSHOT_DIR}" 2>/dev/null | awk '{print "  - Snapshot Size: " $1}' || true
fi

# ============================================================================
# Step 3: 외부 미디어 또는 지정 디렉토리로 복사
# ============================================================================
if [ -n "${EXPORT_PATH}" ]; then
    echo -e "\n${CYAN}[Step 3] Exporting snapshot to destination...${NC}"
    
    # 내보낼 타겟 디렉토리가 없는 경우 자동 생성 시도
    if [ ! -d "${EXPORT_PATH}" ]; then
        echo -e "  - [INFO] Destination directory ${YELLOW}${EXPORT_PATH}${NC} does not exist. Creating..."
        sudo mkdir -p "${EXPORT_PATH}"
    fi

    DEST="${EXPORT_PATH}/prometheus-dump-${TIMESTAMP}"
    echo -e "  - Target Directory: ${YELLOW}${DEST}${NC}"
    
    # 복사 작업 실행
    echo -e "  - Copying files (this may take a few seconds)..."
    sudo mkdir -p "${DEST}"
    sudo cp -r "${SNAPSHOT_DIR}"/* "${DEST}/"
    
    # 복사본 소유권을 현재 유저로 수정하여 복사 후 핸들링 편의성 제공
    sudo chown -R "$(whoami)":"$(whoami)" "${DEST}"

    # 가이드 메타데이터 파일 생성 (DUMP_INFO.txt)
    cat > "${DEST}/DUMP_INFO.txt" << EOF
=== Prometheus TSDB Dump Info ===
Creation Time: $(date)
Snapshot Name: ${SNAPSHOT_NAME}
Source Server: $(hostname)
Source Path: ${SNAPSHOT_DIR}

=== Import Method for External Prometheus ===
1. Stop the target external Prometheus instance.
2. Copy all blocks inside this directory directly into the external Prometheus data directory (e.g. /var/lib/prometheus or /opt/monitoring/prometheus-data).
3. Restart Prometheus.
4. Alternatively, you can spin up a standalone Prometheus pointing directly here:
   prometheus --storage.tsdb.path=${DEST} --web.listen-address=:9091
EOF

    DUMP_SIZE=$(du -sh "${DEST}" | cut -f1)
    echo -e "  - [${GREEN}COMPLETE${NC}] Export finished successfully!"
    echo -e "  - Exported Size: ${GREEN}${DUMP_SIZE}${NC}"
    echo -e "  - Info File    : ${YELLOW}${DEST}/DUMP_INFO.txt${NC}"

    # 디스크 남은 용량 출력
    echo -e "  - Destination Storage Capacity:"
    df -h "${EXPORT_PATH}" | tail -n 1 | awk '{print "    Total: " $2 " | Used: " $3 " | Available: " $4 " (" $5 " used)"}'

    # ============================================================================
    # Step 4: 원본 임시 스냅샷 삭제 (clean 옵션이 들어왔을 때만)
    # ============================================================================
    if [ "${CLEAN_AFTER}" == "clean" ]; then
        echo -e "\n${CYAN}[Step 4] Cleaning up temporary server snapshot...${NC}"
        sudo rm -rf "${SNAPSHOT_DIR}"
        echo -e "  - [${GREEN}COMPLETE${NC}] Temporary snapshot data deleted from server: ${YELLOW}${SNAPSHOT_DIR}${NC}"
    fi
else
    echo -e "\n${YELLOW}[Note] 외부 미디어나 특정 폴더로 백업본을 바로 내보내려면 아래와 같이 사용하세요:${NC}"
    echo -e "  $0 <내보낼_경로>"
    echo -e "  예: $0 /mnt/usb_storage"
    echo -e "  예: $0 /home/user/dumps clean  (백업 완료 후 서버 내부 임시 스냅샷 자동 삭제)"
fi

# ============================================================================
# 서버 내 잔여 스냅샷 현황 출력
# ============================================================================
echo -e "\n${BLUE}----------------------------------------------------------------------${NC}"
echo -e "  ${CYAN}Active Snapshots Remaining on Host Server:${NC}"
if [ -d "${PROMETHEUS_DATA}/snapshots" ] && [ "$(ls -A "${PROMETHEUS_DATA}/snapshots")" ]; then
    sudo ls -lh "${PROMETHEUS_DATA}/snapshots/" 2>/dev/null | tail -n +2 | awk '{print "    " $9 " (" $5 ")"}' || echo "    (None)"
    echo -e "  Total snapshots size on server:"
    sudo du -sh "${PROMETHEUS_DATA}/snapshots" 2>/dev/null | awk '{print "    → Total: " $1}' || true
else
    echo -e "    (No snapshots found on host server)"
fi

echo -e "${BLUE}======================================================================${NC}"
echo -e "${GREEN}             Prometheus Dump Completed Successfully!                  ${NC}"
echo -e "${BLUE}======================================================================${NC}"
