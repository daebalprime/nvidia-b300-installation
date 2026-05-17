#!/bin/bash
###############################################################################
# 04_install_gpu_stack.sh (Verified Package Names)
# Install Driver & CUDA using correct Meta-packages.
###############################################################################
set -euo pipefail

echo "=============================================="
echo " GPU Stack Installation (Precise Mode)"
echo "=============================================="

# 1. 커널 고정 해제 (의존성 충돌 방지) 및 헤더 명시적 설치
# 패키지 설치 시 --no-install-recommends를 사용하여 불필요한 GUI/32비트 패킷 및 커널 업그레이드 유발 패키지를 차단합니다.
echo "[Step 1] Cleaning up holds and installing running kernel headers..."
sudo apt-mark unhold linux-generic linux-image-generic linux-headers-generic || true
sudo apt-get install -y linux-headers-$(uname -r)

# --no-install-recommends로 커널 헤더 메타패키지(linux-headers-generic) 업그레이드 유도를 원천 차단
sudo apt-get install -y --no-install-recommends nvidia-driver-580-open

# 2. CUDA 및 Blackwell 도구 설치
# Step 2: Blackwell 전용 스택 (Pinning이 580.126.20 강제함)
echo "[Step 2] Installing Blackwell-specific tools..."
sudo apt-get install -y \
    nvidia-fabricmanager \
    nvidia-imex \
    nvlink5 \
    nvlsm \
    libnccl2 \
    libnccl-dev \
    doca-runtime \
    doca-sdk \
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
