#!/bin/bash
###############################################################################
# 04_install_gpu_stack.sh (Simplified)
# Install everything directly from network. Locked by Pinning.
###############################################################################
set -euo pipefail

echo "=============================================="
echo " GPU Stack Installation (Locked to 580.126.20)"
echo "=============================================="

# Step 1: 기본 드라이버 및 툴킷
echo "[Step 1] Installing Driver & CUDA..."
sudo apt-get install -y linux-headers-$(uname -r)
sudo apt-get install -y nvidia-driver-580-open cuda-toolkit-13-0

# Step 2: Blackwell 전용 스택 (Pinning 덕분에 126.20 자동 선택됨)
echo "[Step 2] Installing Blackwell stack..."
sudo apt-get install -y \
    nvidia-fabricmanager \
    nvidia-imex \
    nvlsm \
    libnvidia-nscq \
    datacenter-gpu-manager-4-core \
    datacenter-gpu-manager-4-cuda13 \
    datacenter-gpu-manager-4-multinode-cuda13

# 서비스 활성화
sudo systemctl enable --now nvidia-fabricmanager
sudo systemctl enable --now nvidia-imex
sudo systemctl enable --now nvidia-dcgm || true

# Step 3: RDMA & Peermem
echo "[Step 3] Configuring RDMA..."
sudo modprobe nvidia-peermem || true
echo "nvidia-peermem" | sudo tee /etc/modules-load.d/nvidia-peermem.conf > /dev/null

echo "=============================================="
echo " Installation Complete."
echo " Use 04.5_dryrun_verify.sh to confirm versions."
echo "=============================================="
