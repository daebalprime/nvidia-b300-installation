#!/bin/bash
###############################################################################
# 90_purge_nvidia.sh
# [정리] 기존 NVIDIA GPU/CUDA 패키지 전면 제거
#
# 주의: DOCA-OFED(InfiniBand)는 건드리지 않음
###############################################################################
set -euo pipefail

echo "=============================================="
echo " NVIDIA GPU Stack Full Purge"
echo "=============================================="

# 1. NVIDIA 서비스 중지
echo "[Step 1] Stopping NVIDIA services..."
sudo systemctl stop nvidia-fabricmanager 2>/dev/null || true
sudo systemctl stop nvidia-imex 2>/dev/null || true
sudo systemctl disable nvidia-fabricmanager 2>/dev/null || true
sudo systemctl disable nvidia-imex 2>/dev/null || true

# 2. 커널 모듈 언로드
echo "[Step 2] Unloading kernel modules..."
sudo rmmod nvidia-peermem 2>/dev/null || true
sudo rmmod nvidia-uvm 2>/dev/null || true
sudo rmmod nvidia-drm 2>/dev/null || true
sudo rmmod nvidia-modeset 2>/dev/null || true
sudo rmmod nvidia 2>/dev/null || true

# 3. 패키지 전면 제거
echo "[Step 3] Purging all NVIDIA/CUDA packages..."
sudo apt-get purge -y \
    '*nvidia*' \
    '*cuda*' \
    '*cublas*' \
    '*cufft*' \
    '*curand*' \
    '*cusolver*' \
    '*cusparse*' \
    '*npp*' \
    '*nvjpeg*' \
    '*fabricmanager*' \
    '*nvlsm*' \
    '*imex*' \
    '*nscq*' \
    '*nvlink*' \
    '*nvsdm*' \
    '*collectx*' \
    '*mft*' 2>/dev/null || true

sudo apt-get autoremove -y
sudo apt-get autoclean

# 4. NVIDIA 네트워크 리포지토리 제거 (로컬 .deb 방식으로 전환하기 위해)
echo "[Step 4] Removing NVIDIA network repository..."
sudo rm -f /etc/apt/sources.list.d/cuda-ubuntu2404-x86_64.list
sudo rm -f /etc/apt/preferences.d/nvidia-origin-lock
sudo rm -f /etc/apt/preferences.d/nvidia-branch-lock
sudo apt-get update

# 5. 잔여 파일 정리
echo "[Step 5] Cleaning up leftover files..."
sudo rm -f /etc/modules-load.d/nvidia-peermem.conf
sudo rm -f /etc/modprobe.d/nvidia.conf

# 6. 확인
echo ""
echo "=============================================="
echo " Purge Complete"
echo "=============================================="
echo ""
echo " Remaining NVIDIA packages (should be empty):"
dpkg -l | grep -i nvidia | grep "^ii" || echo "  (none — clean)"
echo ""
echo " DOCA-OFED status (should still be intact):"
dpkg -l | grep -i doca | head -3 || echo "  (not installed)"
echo ""
echo " Next: run 01_setup_repos.sh (local .deb mode)"
echo "=============================================="
