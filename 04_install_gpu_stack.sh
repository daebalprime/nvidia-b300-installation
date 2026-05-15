#!/bin/bash
###############################################################################
# 04_install_gpu_stack.sh
# [버전 고정 모드] NVIDIA GPU 드라이버, Fabric Manager, CUDA 정밀 설치
#
# 주의: 이 스크립트는 595 등 다른 버전의 침투를 방지하기 위해 버전을 강제 고정합니다.
###############################################################################
set -euo pipefail

# 캡처 화면에서 확인된 580 브랜치 최신 버전
V="580.159.04-1ubuntu1"

echo "=============================================="
echo " GPU Stack Force Installation (Version: $V)"
echo "=============================================="

# 1. 기존 꼬인 패키지 전면 제거
echo "[Step 1] Purging mismatched packages..."
sudo apt-get purge -y "*nvidia*" "*cuda*" "*fabricmanager*" "*nvlsm*" "*imex*" || true
sudo apt-get autoremove -y && sudo apt-get autoclean

# 2. 드라이버 및 커널 모듈 설치 (버전 강제 고정)
echo "[Step 2] Installing NVIDIA Driver & DKMS ($V)..."
sudo apt-get install -y \
    nvidia-driver-580-open=$V \
    nvidia-dkms-580-open=$V \
    nvidia-utils-580=$V \
    libnvidia-cfg1-580=$V \
    libnvidia-common-580=$V \
    libnvidia-compute-580=$V \
    libnvidia-decode-580=$V \
    libnvidia-encode-580=$V \
    libnvidia-fbc1-580=$V \
    libnvidia-gl-580=$V \
    nvidia-kernel-common-580-server \
    nvidia-kernel-source-580-open=$V

# 3. Fabric Manager 및 IMEX 버전 강제 고정
# Note: 리포지토리에 따라 FM 버전 문자열이 미세하게 다를 수 있으니 실패 시 madison 확인 필요
echo "[Step 3] Installing Fabric Manager & IMEX ($V)..."
sudo apt-get install -y \
    nvidia-fabricmanager-580=$V \
    nvidia-imex=$V \
    libnvidia-nscq-580=$V || \
    echo "  [WARNING] Exact version match for FM/IMEX failed. Installing latest available 580..." && \
    sudo apt-get install -y nvidia-fabricmanager-580 nvidia-imex libnvidia-nscq-580

sudo systemctl enable --now nvidia-fabricmanager
sudo systemctl enable --now nvidia-imex

# 4. CUDA Toolkit 설치
echo "[Step 4] Installing CUDA Toolkit 13.0..."
sudo apt-get install -y cuda-toolkit-13-0

# 5. GPUDirect RDMA (nvidia-peermem) 및 최적화
echo "[Step 5] Finalizing configurations..."
sudo modprobe nvidia-peermem || true
echo "nvidia-peermem" | sudo tee /etc/modules-load.d/nvidia-peermem.conf > /dev/null
echo "options nvidia NVreg_EnablePCIERelaxedOrderingMode=1" | sudo tee /etc/modprobe.d/nvidia.conf > /dev/null

echo "=============================================="
echo " GPU Stack Installation Complete (Fixed Version)"
echo " [CHECK] dpkg -l | grep nvidia"
echo "=============================================="
