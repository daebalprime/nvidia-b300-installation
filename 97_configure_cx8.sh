#!/bin/bash
###############################################################################
# 97_configure_cx8.sh
# [하드웨어 최적화] ConnectX-8 (CX8) 어댑터 일괄 설정
#
# 주의: 이 스크립트 실행 후 반드시 'COLD REBOOT'이 필요합니다.
###############################################################################
set -euo pipefail

# Blackwell HGX B300 최적 파라미터
PARAMS="MODULE_SPLIT_M0[0..3]=1 MODULE_SPLIT_M0[4..15]=FF NUM_OF_PLANES_P1=0 LINK_TYPE_P1=1 NUM_OF_PF=1"

echo "=============================================="
echo " ConnectX-8 (CX8) Configuration Tool (Precision Mode)"
echo "=============================================="

sudo mst start 2>/dev/null || true

if ! command -v mlxconfig &> /dev/null; then
    echo "[ERROR] mlxconfig not found."
    exit 1
fi

DEVICES=$(ls /sys/class/infiniband/ 2>/dev/null || echo "")

for dev in $DEVICES; do
    printf "  Checking %-10s : " "$dev"
    
    # mlxconfig 쿼리 전체 결과를 읽어옴
    FULL_QUERY=$(sudo mlxconfig -d "$dev" q 2>/dev/null || true)
    
    # 1. "ConnectX-8" 또는 "ConnectX8" 키워드 존재 여부 확인
    # 2. 다른 세대(ConnectX-6 등)의 오탐지 방지
    if echo "$FULL_QUERY" | grep -Ei "ConnectX-?8" | grep -qvE "ConnectX-?[0-79]"; then
        # 상세 모델명 정보 추출 (Description 필드 선호)
        MODEL_INFO=$(echo "$FULL_QUERY" | grep -Ei "Description|Part Number" | head -n 1 | cut -d: -f2- | xargs || echo "ConnectX-8")
        echo "[CX8 Detected: $MODEL_INFO] Applying Blackwell optimization..."
        sudo mlxconfig -d "$dev" -y set $PARAMS
    else
        echo "[Skipped] Not a CX8 Device"
    fi
done

echo ""
echo "=============================================="
echo " Configuration complete!"
echo " [IMPORTANT] COLD REBOOT (Power Cycle) is required."
echo "=============================================="
