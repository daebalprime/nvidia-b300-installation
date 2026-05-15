#!/bin/bash
###############################################################################
# 04_install_gpu_stack.sh
# [온라인 환경용] NVIDIA GPU 드라이버, NVLink5 스택, CUDA Toolkit 설치
###############################################################################
set -euo pipefail

DRIVER_VERSION="580"

echo "=============================================="
echo " GPU Stack Installation (Blackwell Optimized)"
echo "=============================================="

# 1. GPU 드라이버 설치 (Open Kernel Module 필수)
echo "[Step 1] Installing NVIDIA Driver ${DRIVER_VERSION}-open..."
sudo apt-get install -y \
    nvidia-driver-${DRIVER_VERSION}-open \
    nvidia-dkms-${DRIVER_VERSION}-open \
    nvidia-utils-${DRIVER_VERSION}

# 2. Fabric Manager 및 NVLink 스택 설치
echo "[Step 2] Installing Fabric Manager and NVLink5 tools..."
sudo apt-get install -y \
    nvidia-fabricmanager-${DRIVER_VERSION} \
    nvidia-imex \
    nvlsm \
    libnvsdm \
    libnvidia-nscq

sudo systemctl enable --now nvidia-fabricmanager
sudo systemctl enable --now nvidia-imex

# 3. CUDA Toolkit 설치
echo "[Step 3] Installing CUDA Toolkit 13.0..."
sudo apt-get install -y cuda-toolkit-13-0

# 4. GPUDirect RDMA (nvidia-peermem) 설정
echo "[Step 4] Configuring GPUDirect RDMA..."
sudo modprobe nvidia-peermem || echo "  [WARNING] nvidia-peermem load failed. Reboot may be required."
echo "nvidia-peermem" | sudo tee /etc/modules-load.d/nvidia-peermem.conf > /dev/null

# 5. PCIe Relaxed Ordering 최적화
echo "options nvidia NVreg_EnablePCIERelaxedOrderingMode=1" | sudo tee /etc/modprobe.d/nvidia.conf > /dev/null

echo "=============================================="
echo " GPU Stack installation complete!"
echo " Please reboot to apply all kernel changes."
echo "=============================================="
