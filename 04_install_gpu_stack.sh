#!/bin/bash
###############################################################################
# 04_install_gpu_stack.sh
# [로컬 .deb 방식] NVIDIA GPU 스택 설치 — 580.126.20 통일
#
# 전제: 01_setup_repos.sh에서 로컬 리포 등록 완료
# 로컬 리포 경로:
#   /var/nvidia-driver-local-repo-ubuntu2404-580.126.20/
#   /var/cuda-repo-ubuntu2404-13-0-local/
###############################################################################
set -euo pipefail

DRIVER_VERSION="580.126.20"

echo "=============================================="
echo " GPU Stack Installation (Local Repo / ${DRIVER_VERSION})"
echo "=============================================="

# 0. 네트워크 리포 강제 제거 (cuda-keyring이 다시 등록했을 수 있음)
echo "[Step 0] Blocking NVIDIA network repo (159.04 prevention)..."
# cuda-keyring이 등록하는 모든 네트워크 소스 제거
for f in /etc/apt/sources.list.d/cuda*.list; do
    if [ -f "$f" ] && grep -q "developer.download.nvidia.com" "$f" 2>/dev/null; then
        echo "  Removing network repo: $f"
        sudo rm -f "$f"
    fi
done
# /etc/apt/sources.list.d/ 하위에 cuda-keyring이 만든 .sources 파일도 제거
for f in /etc/apt/sources.list.d/cuda*.sources; do
    if [ -f "$f" ] && grep -q "developer.download.nvidia.com" "$f" 2>/dev/null; then
        echo "  Removing network source: $f"
        sudo rm -f "$f"
    fi
done
sudo apt-get update

# 진단: 현재 등록된 NVIDIA 관련 리포 출력
echo "[Diag] Active NVIDIA repos:"
apt-cache policy | grep -E "nvidia|cuda|file:/var" || true
echo ""

# 0.1 로컬 리포 등록 확인
if ! apt-cache policy | grep -q "file:/var/nvidia-driver-local\|file:/var/cuda-repo"; then
    echo "[ERROR] Local repo not found. Run 01_setup_repos.sh first."
    exit 1
fi

# 0.2 candidate 확인
echo "[Check] nvidia-driver-580-open candidate:"
apt-cache policy nvidia-driver-580-open | head -5
echo "[Check] nvlink5-580 candidate:"
apt-cache policy nvlink5-580 | head -5

# 1. 드라이버 설치 (로컬 리포 — Open Kernel / Blackwell 필수)
echo ""
echo "[Step 1] Installing NVIDIA Driver (Open / ${DRIVER_VERSION})..."
sudo apt-get install -y \
    nvidia-driver-580-open \
    nvidia-dkms-580-open \
    nvidia-utils-580

# 2. NVLink5 스택 (로컬 리포에서 — FM + IMEX + NSCQ 일괄)
echo "[Step 2] Installing NVLink5 stack..."
sudo apt-get install -y \
    nvlink5-580 \
    nvidia-fabricmanager \
    nvidia-imex \
    libnvidia-nscq \
    libnvsdm

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
    echo -e "\n\e[32m [OK] Clean ${DRIVER_VERSION} stack.\e[0m"
fi

echo ""
echo " Please reboot to apply kernel changes."
echo "=============================================="
