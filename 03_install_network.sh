#!/bin/bash
###############################################################################
# 03_install_network.sh
# [온라인 환경용] DOCA-OFED 설치 (InfiniBand/RoCE)
#
# 중요: GPU 드라이버보다 먼저 설치해야 nvidia-peermem이 정상 링크됩니다.
###############################################################################
set -euo pipefail

echo "=============================================="
echo " Network Stack Installation (DOCA-OFED)"
echo "=============================================="

# 1. 충돌 패키지 제거
echo "[Step 1] Removing conflicting inbox RDMA packages..."
sudo apt-get remove -y \
    libipathverbs1 librdmacm1 libibverbs1 libmthca1 libmlx4-1 \
    ibverbs-utils infiniband-diags ibutils perftest 2>/dev/null || true

# 2. DOCA-OFED 설치
# 사용자 환경에 따라 doca-ofed (최소) 또는 doca-all (전체) 선택 가능
# 여기서는 PoC 표준인 doca-ofed를 기본으로 설치합니다.
echo "[Step 2] Installing doca-ofed..."
sudo apt-get install -y doca-ofed

# 3. 서비스 시작
echo "[Step 3] Starting OFED services..."
sudo /etc/init.d/openibd restart || true

echo "=============================================="
echo " Network installation complete!"
echo " [NOTICE] opensm 및 추가 유틸리티 설정은 제외되었습니다."
echo "=============================================="
