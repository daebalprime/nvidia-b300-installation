#!/bin/bash
###############################################################################
# 04_install_gpu_stack.sh (The Cleanest Version)
# Uses Meta-packages + Pinning to minimize maintenance.
###############################################################################
set -euo pipefail

echo "=============================================="
echo " GPU Stack Installation (Meta-package Mode)"
echo "=============================================="

# 1. 드라이버 + CUDA 메타 패키지 설치
# nvidia-driver-580-open-cuda 는 드라이버와 CUDA를 동시에 보장합니다.
echo "[Step 1] Installing Driver & CUDA Meta-packages..."
sudo apt-get install -y linux-headers-$(uname -r)
sudo apt-get install -y nvidia-driver-580-open-cuda cuda-toolkit-13-0

# 2. Blackwell 특화 서비스 및 도구 (Pinning이 580.126.20 강제함)
echo "[Step 2] Installing Blackwell-specific tools..."
sudo apt-get install -y \
    nvidia-fabricmanager \
    nvidia-imex \
    datacenter-gpu-manager-4-core \
    datacenter-gpu-manager-4-multinode-cuda13

# 서비스 활성화
sudo systemctl enable --now nvidia-fabricmanager
sudo systemctl enable --now nvidia-imex
sudo systemctl enable --now nvidia-dcgm || true

# 3. GPUDirect RDMA 설정
echo "[Step 3] Configuring RDMA..."
sudo modprobe nvidia-peermem || true
echo "nvidia-peermem" | sudo tee /etc/modules-load.d/nvidia-peermem.conf > /dev/null

echo "=============================================="
echo " Installation Complete! No more local repo mess."
echo "=============================================="
