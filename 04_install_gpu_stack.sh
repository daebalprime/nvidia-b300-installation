#!/bin/bash
###############################################################################
# 04_install_gpu_stack.sh
# [로컬 .deb 방식] NVIDIA GPU 스택 설치 — 580.126.20 통일
#
# 전제: 01_setup_repos.sh에서 로컬 리포 등록 + NVLink .deb 다운로드 완료
###############################################################################
set -euo pipefail

DL_DIR="/tmp/nvidia-debs"

echo "=============================================="
echo " GPU Stack Installation (Local Repo / 580.126.20)"
echo "=============================================="

# 0. 로컬 리포 등록 확인
if ! apt-cache policy | grep -q "nvidia-driver-local\|cuda.*local"; then
    echo "[ERROR] Local repo not found. Run 01_setup_repos.sh first."
    exit 1
fi

# 1. 드라이버 설치 (로컬 리포에서 — Open Kernel)
echo "[Step 1] Installing NVIDIA Driver (Open / 580.126.20)..."
sudo apt-get install -y \
    nvidia-driver-580-open \
    nvidia-dkms-580-open \
    nvidia-utils-580

# 2. NVLink5 스택 설치
echo "[Step 2] Installing NVLink5 stack..."

# 로컬 리포에 nvlink5-580이 있으면 apt로, 없으면 직접 dpkg -i
if apt-cache show nvlink5-580 2>/dev/null | grep -q "580.126.20"; then
    echo "  Installing via apt (local repo)..."
    sudo apt-get install -y nvlink5-580
else
    echo "  Installing via dpkg (downloaded .deb files)..."
    # 개별 패키지 직접 설치
    sudo dpkg -i \
        "$DL_DIR/nvidia-fabricmanager_580.126.20-1_amd64.deb" \
        "$DL_DIR/nvidia-imex_580.126.20-1_amd64.deb" \
        "$DL_DIR/libnvidia-nscq_580.126.20-1_amd64.deb" \
        "$DL_DIR/libnvsdm_580.126.20-1_amd64.deb" \
        "$DL_DIR/nvlink5-580_580.126.20-1_amd64.deb" \
        "$DL_DIR/nvlink5_580.126.20-1_amd64.deb" \
        2>/dev/null || true
    sudo apt-get install -f -y  # 의존성 해결
fi

sudo systemctl enable --now nvidia-fabricmanager
sudo systemctl enable --now nvidia-imex

# 3. CUDA Toolkit (로컬 리포에서)
echo "[Step 3] Installing CUDA Toolkit 13.0..."
sudo apt-get install -y cuda-toolkit-13-0

# 4. GPUDirect RDMA
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

if dpkg -l | grep nvidia | grep -qE "159\.|595\."; then
    echo -e "\n\e[31m [WARNING] Version contamination detected!\e[0m"
else
    echo -e "\n\e[32m [OK] Clean 580.126.20 stack.\e[0m"
fi

echo ""
echo " Please reboot to apply kernel changes."
echo "=============================================="
