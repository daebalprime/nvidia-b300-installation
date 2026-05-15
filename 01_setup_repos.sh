#!/bin/bash
###############################################################################
# 01_setup_repos.sh
# [온라인 환경용] NVIDIA 로컬 리포지토리 .deb 다운로드 + 등록
#
# 오프라인 스크립트(scripts_offline/01_prepare_seed_machine_apt.sh)에서
# 검증된 동일한 URL과 방법론을 그대로 사용
###############################################################################
set -euo pipefail

DRIVER_VERSION="580.126.20"
DRIVER_BRANCH="580"
CUDA_VERSION="13.0.2"
CUDA_DRIVER_VERSION="580.95.05"

DL_DIR="/tmp/nvidia-debs"
mkdir -p "$DL_DIR"

echo "=============================================="
echo " Repository Setup (Local .deb — ${DRIVER_VERSION})"
echo "=============================================="

# 1. 필수 도구
echo "[Step 1] Installing prerequisites..."
sudo apt-get update
sudo apt-get install -y gnupg2 curl ca-certificates wget

# 2. 기존 NVIDIA 네트워크 리포 제거 (159.04 오염 방지)
echo "[Step 2] Removing NVIDIA network repo (if exists)..."
sudo rm -f /etc/apt/sources.list.d/cuda-ubuntu2404-x86_64.list
sudo rm -f /etc/apt/preferences.d/nvidia-*

# 3. GPU Driver Local Repo 다운로드 + 등록
#    (오프라인 스크립트와 동일한 URL)
DRIVER_DEB="${DL_DIR}/nvidia-driver-local-repo-ubuntu2404-${DRIVER_VERSION}_1.0-1_amd64.deb"
echo "[Step 3] Downloading GPU Driver Local Repo (~754MB)..."
if [ ! -f "$DRIVER_DEB" ]; then
    wget -q --show-progress -O "$DRIVER_DEB" \
        "https://developer.download.nvidia.com/compute/nvidia-driver/${DRIVER_VERSION}/local_installers/nvidia-driver-local-repo-ubuntu2404-${DRIVER_VERSION}_1.0-1_amd64.deb"
fi
echo "  Registering driver local repo..."
sudo dpkg -i "$DRIVER_DEB"
sudo cp /var/nvidia-driver-local-repo-ubuntu2404-*/nvidia-driver-local-*-keyring.gpg /usr/share/keyrings/ 2>/dev/null || true

# 4. CUDA Toolkit Local Repo 다운로드 + 등록
CUDA_DEB="${DL_DIR}/cuda-repo-ubuntu2404-13-0-local_${CUDA_VERSION}-${CUDA_DRIVER_VERSION}-1_amd64.deb"
echo "[Step 4] Downloading CUDA Toolkit Local Repo (~4GB)..."
if [ ! -f "$CUDA_DEB" ]; then
    wget -q --show-progress -O "$CUDA_DEB" \
        "https://developer.download.nvidia.com/compute/cuda/${CUDA_VERSION}/local_installers/cuda-repo-ubuntu2404-13-0-local_${CUDA_VERSION}-${CUDA_DRIVER_VERSION}-1_amd64.deb"
fi
echo "  Registering CUDA local repo..."
sudo dpkg -i "$CUDA_DEB"
sudo cp /var/cuda-repo-ubuntu2404-13-0-local/cuda-*-keyring.gpg /usr/share/keyrings/ 2>/dev/null || true

# 5. CUDA Keyring
echo "[Step 5] Installing CUDA Keyring..."
KEYRING_DEB="${DL_DIR}/cuda-keyring_1.1-1_all.deb"
if [ ! -f "$KEYRING_DEB" ]; then
    wget -q --show-progress -O "$KEYRING_DEB" \
        "https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2404/x86_64/cuda-keyring_1.1-1_all.deb"
fi
sudo dpkg -i "$KEYRING_DEB"

# 6. DOCA 리포지토리 (OFED 용)
echo "[Step 6] Adding NVIDIA DOCA repository..."
wget -qO - --no-check-certificate https://linux.mellanox.com/public/repo/doca/3.2.1/ubuntu24.04/x86_64/GPG-KEY-Mellanox.pub 2>/dev/null | \
    sudo gpg --dearmor -o /usr/share/keyrings/mellanox.gpg --yes || true
echo "deb [signed-by=/usr/share/keyrings/mellanox.gpg] https://linux.mellanox.com/public/repo/doca/3.2.1/ubuntu24.04/x86_64/ /" | \
    sudo tee /etc/apt/sources.list.d/doca.list

# 7. APT 업데이트
echo "[Step 7] Updating APT cache..."
sudo apt-get update

echo "=============================================="
echo " Repository setup complete!"
echo " Driver local repo: ${DRIVER_VERSION} (126.20)"
echo " CUDA local repo: ${CUDA_VERSION} (95.05 base)"
echo " DOCA repo: 3.2.1"
echo "=============================================="
