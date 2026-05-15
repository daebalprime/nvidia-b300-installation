#!/bin/bash
###############################################################################
# 04_install_gpu_stack.sh (Verified Package Names)
# Install Driver & CUDA using correct Meta-packages.
###############################################################################
set -euo pipefail

echo "=============================================="
echo " GPU Stack Installation (Precise Mode)"
echo "=============================================="

# 1. 드라이버 및 커널 헤더 설치
# Blackwell은 반드시 'open' 드라이버를 써야 합니다.
echo "[Step 1] Installing Open Kernel Driver..."
sudo apt-get install -y linux-headers-$(uname -r)
sudo apt-get install -y nvidia-driver-580-open

# 2. CUDA 및 Blackwell 도구 설치
# Pinning 패키지가 이미 580.126.20을 강제하므로 아래 명령어로 모든 의존성이 해결됩니다.
echo "[Step 2] Installing CUDA & Blackwell stack..."
sudo apt-get install -y cuda-toolkit-13-0 \
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
echo " Installation Complete!"
echo " Please reboot to apply driver changes."
echo "=============================================="
