#!/bin/bash
###############################################################################
# 04_install_gpu_stack.sh
# [온라인] NVIDIA GPU 스택 설치 — 580.126.20 통일
#
# 전략:
#   nvlink5-580=580.126.20-2 메타패키지로 NVLink 스택 전체를 한 세트로 설치
#   nvidia-driver-580-open=580.126.20-1ubuntu1 으로 드라이버 버전 고정
###############################################################################
set -euo pipefail

# 버전 고정 (진단 결과 기준)
DRV_V="580.126.20-1ubuntu1"
NVL_V="580.126.20-2"

echo "=============================================="
echo " GPU Stack Installation"
echo " Driver: $DRV_V"
echo " NVLink: $NVL_V"
echo "=============================================="

# 1. 기존 꼬인 패키지 제거
echo "[Step 1] Purging existing NVIDIA packages..."
sudo apt-get purge -y '*nvidia*' '*cuda*' '*fabricmanager*' '*nvlsm*' '*imex*' '*nscq*' || true
sudo apt-get autoremove -y && sudo apt-get autoclean

# 2. 드라이버 설치 (Open Kernel — Blackwell 필수)
echo "[Step 2] Installing NVIDIA Driver ($DRV_V)..."
sudo apt-get install -y \
    nvidia-driver-580-open="$DRV_V" \
    nvidia-dkms-580-open="$DRV_V" \
    nvidia-utils-580="$DRV_V"

# 3. NVLink5 스택 (FM + IMEX + NSCQ + MFT 등 일괄 설치)
echo "[Step 3] Installing NVLink5 stack via nvlink5-580 ($NVL_V)..."
sudo apt-get install -y nvlink5-580="$NVL_V"

sudo systemctl enable --now nvidia-fabricmanager
sudo systemctl enable --now nvidia-imex

# 4. CUDA Toolkit
echo "[Step 4] Installing CUDA Toolkit 13.0..."
sudo apt-get install -y cuda-toolkit-13-0

# 5. GPUDirect RDMA + 최적화
echo "[Step 5] Configuring GPUDirect RDMA..."
sudo modprobe nvidia-peermem || true
echo "nvidia-peermem" | sudo tee /etc/modules-load.d/nvidia-peermem.conf > /dev/null
echo "options nvidia NVreg_EnablePCIERelaxedOrderingMode=1" | sudo tee /etc/modprobe.d/nvidia.conf > /dev/null

# 6. 설치 후 버전 검증
echo ""
echo "=============================================="
echo " Post-install Version Check"
echo "=============================================="
echo ""
dpkg -l | grep -E "nvidia-driver|fabricmanager|imex|nscq|nvlink5" | awk '{printf "  %-40s %s\n", $2, $3}'

# 595 오염 체크
if dpkg -l | grep nvidia | grep -q "595"; then
    echo ""
    echo -e "\e[31m [WARNING] 595 branch contamination detected!\e[0m"
else
    echo ""
    echo -e "\e[32m [OK] Clean 580.126.20 stack.\e[0m"
fi

echo ""
echo " Please reboot to apply kernel changes."
echo "=============================================="
