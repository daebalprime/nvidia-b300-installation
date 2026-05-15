#!/bin/bash
###############################################################################
# 04_install_gpu_stack.sh
# [로컬 .deb 방식] NVIDIA GPU 스택 설치 — 580.126.20 통일
#
# 전제: 01_setup_repos.sh에서 로컬 .deb 인스톨러가 등록된 상태
# 로컬 리포에는 126.20 세트만 있으므로 버전 충돌 불가
###############################################################################
set -euo pipefail

echo "=============================================="
echo " GPU Stack Installation (Local Repo / 580.126.20)"
echo "=============================================="

# 0. 로컬 리포 등록 확인
if ! apt-cache policy | grep -q "cuda.*local"; then
    echo "[ERROR] CUDA local repo not found."
    echo "  Please run 01_setup_repos.sh first."
    exit 1
fi

# 1. 드라이버 설치 (Open Kernel — Blackwell 필수)
echo "[Step 1] Installing NVIDIA Driver (Open)..."
sudo apt-get install -y \
    nvidia-driver-580-open \
    nvidia-dkms-580-open \
    nvidia-utils-580

# 2. NVLink5 스택 (FM + IMEX + NSCQ + MFT 일괄)
echo "[Step 2] Installing NVLink5 stack..."
sudo apt-get install -y nvlink5-580

sudo systemctl enable --now nvidia-fabricmanager
sudo systemctl enable --now nvidia-imex

# 3. CUDA Toolkit
echo "[Step 3] Installing CUDA Toolkit 13.0..."
sudo apt-get install -y cuda-toolkit-13-0

# 4. GPUDirect RDMA + 최적화
echo "[Step 4] Configuring GPUDirect RDMA..."
sudo modprobe nvidia-peermem || true
echo "nvidia-peermem" | sudo tee /etc/modules-load.d/nvidia-peermem.conf > /dev/null
echo "options nvidia NVreg_EnablePCIERelaxedOrderingMode=1" | sudo tee /etc/modprobe.d/nvidia.conf > /dev/null

# 5. 설치 후 버전 검증
echo ""
echo "=============================================="
echo " Post-install Version Check"
echo "=============================================="
dpkg -l | grep -E "nvidia-driver|fabricmanager|imex|nscq|nvlink5" | awk '{printf "  %-40s %s\n", $2, $3}'

# 버전 통일 체크 — 126.20 외의 버전이 있으면 경고
if dpkg -l | grep nvidia | grep -qE "159\.|595\."; then
    echo -e "\n\e[31m [WARNING] Non-126.20 version detected!\e[0m"
else
    echo -e "\n\e[32m [OK] Clean 580.126.20 stack.\e[0m"
fi

echo ""
echo " Please reboot to apply kernel changes."
echo "=============================================="
