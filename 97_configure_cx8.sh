#!/bin/bash
###############################################################################
# 97_configure_cx8.sh
# [하드웨어 최적화] ConnectX-8 (CX8) 어댑터 일괄 설정
#
# 주의: 이 스크립트 실행 후 반드시 'COLD REBOOT'이 필요합니다.
###############################################################################
set -euo pipefail

# Blackwell HGX B300 최적 파라미터
# MODULE_SPLIT: 800G 분할
# LINK_TYPE: 1 (InfiniBand)
# NUM_OF_PF: 1 (Single Port)
PARAMS="MODULE_SPLIT_M0[0..3]=1 MODULE_SPLIT_M0[4..15]=FF NUM_OF_PLANES_P1=0 LINK_TYPE_P1=1 NUM_OF_PF=1"

echo "=============================================="
echo " ConnectX-8 (CX8) Configuration Tool"
echo "=============================================="

# MST 서비스 시작 (장치 인식 보장)
sudo mst start 2>/dev/null || true

if ! command -v mlxconfig &> /dev/null; then
    echo "[ERROR] mlxconfig not found. Please install MFT (included in DOCA-OFED)."
    exit 1
fi

DEVICES=$(ls /sys/class/infiniband/ 2>/dev/null || echo "")

if [ -z "$DEVICES" ]; then
    echo "[ERROR] No InfiniBand devices found. Check OFED driver status."
    exit 1
fi

for dev in $DEVICES; do
    printf "  Checking %-10s : " "$dev"
    
    # CX8 장치 식별 및 설정 적용 (ConnectX8 또는 X8 키워드 검색)
    if sudo mlxconfig -d "$dev" q 2>/dev/null | grep -Ei "ConnectX8|X8"; then
        echo "[CX8 Detected] Applying Blackwell optimization..."
        sudo mlxconfig -d "$dev" -y set $PARAMS
    else
        echo "[Skipped] Not a ConnectX-8 device"
    fi
done

echo ""
echo "=============================================="
echo " Configuration complete!"
echo " [IMPORTANT] COLD REBOOT (Power Cycle) is required."
echo "=============================================="
