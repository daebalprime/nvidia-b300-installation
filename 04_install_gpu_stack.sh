#!/bin/bash
###############################################################################
# 04_install_gpu_stack.sh
# NVIDIA GPU 스택 설치 — 580.126.20
#
# DCGM 4.5.3-1 대응 (패키지명 변경됨)
###############################################################################
set -euo pipefail

DRIVER_VERSION="580"

echo "=============================================="
echo " GPU Stack Installation"
echo "=============================================="

# 사전 검증: Nouveau
if lsmod | grep -q nouveau; then
    echo "[ERROR] Nouveau is loaded. Please run script 03 and reboot."
    exit 1
fi

# Step 1: GPU 드라이버
echo "[Step 1] Installing GPU Driver..."
echo "  → Ensuring kernel headers for $(uname -r) are installed..."
sudo apt-get install -y linux-headers-$(uname -r)
sudo apt-get install -y nvidia-driver-${DRIVER_VERSION}-open

# Step 2: NVLink5 스택
echo "[Step 2] Installing NVLink5 stack..."
sudo apt-get install -y \
    nvidia-driver-580-open \
    nvidia-dkms-580-open \
    nvidia-utils-580 \
    nvidia-fabricmanager \
    nvidia-imex

echo "options nvidia NVreg_OpenRmEnableUnsupportedGpus=1" | sudo tee /etc/modprobe.d/nvidia-open.conf > /dev/null
sudo apt-get install -y \
    nvlsm \
    libnvsdm \
    libnvidia-nscq \
    mft || true

sudo systemctl enable --now nvidia-fabricmanager
sudo systemctl enable --now nvidia-imex

# Step 3: CUDA Toolkit
echo "[Step 3] Installing CUDA Toolkit..."
sudo apt-get install -y cuda-toolkit-13-0

# Step 4: auxiliary packages (DCGM 4.x 최신, NCCL, GDS)
echo "[Step 4] Installing auxiliary packages (DCGM 4.5.3, NCCL, GDS)..."
# DCGM 4.x 패키지명 명시적 설치
sudo apt-get install -y \
    datacenter-gpu-manager-4-core \
    datacenter-gpu-manager-4-cuda13 \
    datacenter-gpu-manager-4-multinode-cuda13 || true

# DCGM 서비스 시작 (공식 명칭 확인)
if systemctl list-unit-files | grep -q nvidia-dcgm; then
    sudo systemctl enable --now nvidia-dcgm || true
elif systemctl list-unit-files | grep -q dcgm; then
    sudo systemctl enable --now dcgm || true
fi

sudo apt-get install -y libnccl2 libnccl-dev || true
sudo apt-get install -y nvidia-gds-13-0 || true

# Step 5: GPUDirect RDMA
echo "[Step 5] Configuring GPUDirect RDMA..."
sudo modprobe nvidia-peermem || true
echo "nvidia-peermem" | sudo tee /etc/modules-load.d/nvidia-peermem.conf > /dev/null
echo "options nvidia NVreg_EnablePCIERelaxedOrderingMode=1" | sudo tee /etc/modprobe.d/nvidia.conf > /dev/null

# Step 6: 검증
echo ""
echo "=============================================="
echo " Post-install Version Check"
echo "=============================================="
dpkg -l | grep -E "nvidia-driver|fabricmanager|imex|nscq|nvlink5|dcgm" | awk '{printf "  %-40s %s\n", $2, $3}'

if dpkg -l | grep nvidia | grep -qE "159\.|595\."; then
    echo -e "\n\e[31m [WARNING] Version contamination detected!\e[0m"
else
    echo -e "\n\e[32m [OK] Clean 580.126.20 stack.\e[0m"
fi

echo ""
echo " Please reboot to apply kernel changes."
echo "=============================================="
