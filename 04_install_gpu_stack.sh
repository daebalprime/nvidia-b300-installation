#!/bin/bash
###############################################################################
# 04_install_gpu_stack.sh
# NVIDIA GPU 스택 설치 — 580.126.20
#
# 오프라인 04와 동일한 설치 로직 (apt-get install만 사용)
# 전제: 01_setup_repos.sh에서 3-Layer 리포 등록 완료
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

# Step 1: GPU 드라이버 (Open Kernel Module - Blackwell 필수)
echo "[Step 1] Installing GPU Driver..."
echo "  → Ensuring kernel headers for $(uname -r) are installed..."
sudo apt-get install -y linux-headers-$(uname -r)

sudo apt-get install -y nvidia-driver-${DRIVER_VERSION}-open

# Step 2: NVLink5 스택 (FM + IMEX + NSCQ + MFT)
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

echo "[Step 4] Installing auxiliary packages..."
sudo apt-get install -y datacenter-gpu-manager || true
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
dpkg -l | grep -E "nvidia-driver|fabricmanager|imex|nscq|nvlink5" | awk '{printf "  %-40s %s\n", $2, $3}'

if dpkg -l | grep nvidia | grep -qE "159\.|595\."; then
    echo -e "\n\e[31m [WARNING] Version contamination detected!\e[0m"
else
    echo -e "\n\e[32m [OK] Clean 580.126.20 stack.\e[0m"
fi

echo ""
echo " Please reboot to apply kernel changes."
echo " Next: 05_install_container.sh"
echo "=============================================="
