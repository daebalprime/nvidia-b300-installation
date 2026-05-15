#!/bin/bash
###############################################################################
# 01_setup_repos.sh
# [온라인 환경용] NVIDIA 로컬 리포지토리 .deb 다운로드 + 등록
#
# 전략 (오프라인과 동일):
#   1. nvidia-driver-local-repo .deb → 드라이버 + 라이브러리 126.20 세트
#   2. cuda-repo-local .deb → CUDA Toolkit 13.0.2 세트
#   3. FM/IMEX/NSCQ 개별 .deb → NVLink5 스택
#   → 네트워크 repo 사용하지 않음 = 159.04 오염 없음
###############################################################################
set -euo pipefail

# 다운로드 디렉토리
DL_DIR="/tmp/nvidia-debs"
mkdir -p "$DL_DIR"

# NVIDIA 공식 다운로드 URL
# (오프라인 번들에서 확인된 정확한 파일명 기준)
BASE_URL="https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2404/x86_64"
DRIVER_REPO_URL="https://developer.download.nvidia.com/compute/nvidia-driver/repos/ubuntu2404/x86_64/nvidia-driver-local-repo-ubuntu2404-580.126.20_1.0-1_amd64.deb"
CUDA_REPO_URL="https://developer.download.nvidia.com/compute/cuda/13.0.2/local_installers/cuda-repo-ubuntu2404-13-0-local_13.0.2-580.95.05-1_amd64.deb"

# NVLink 스택 개별 패키지 (NVIDIA CUDA repo에서 직접 다운로드)
NVLINK_PKGS=(
    "${BASE_URL}/nvidia-fabricmanager_580.126.20-1_amd64.deb"
    "${BASE_URL}/nvidia-imex_580.126.20-1_amd64.deb"
    "${BASE_URL}/libnvidia-nscq_580.126.20-1_amd64.deb"
    "${BASE_URL}/libnvsdm_580.126.20-1_amd64.deb"
    "${BASE_URL}/nvlink5-580_580.126.20-1_amd64.deb"
    "${BASE_URL}/nvlink5_580.126.20-1_amd64.deb"
)

echo "=============================================="
echo " Repository Setup (Local .deb Mode — 580.126.20)"
echo "=============================================="

# 1. 필수 도구
echo "[Step 1] Installing prerequisites..."
sudo apt-get update
sudo apt-get install -y gnupg2 curl ca-certificates wget

# 2. 기존 NVIDIA 네트워크 리포 제거 (159.04 오염 방지)
echo "[Step 2] Removing NVIDIA network repo (if exists)..."
sudo rm -f /etc/apt/sources.list.d/cuda-ubuntu2404-x86_64.list
sudo rm -f /etc/apt/preferences.d/nvidia-*

# 3. 드라이버 로컬 리포 다운로드 + 등록
echo "[Step 3] Downloading NVIDIA Driver local repo (~754MB)..."
DRIVER_DEB="$DL_DIR/nvidia-driver-local-repo.deb"
if [ ! -f "$DRIVER_DEB" ]; then
    wget -O "$DRIVER_DEB" "$DRIVER_REPO_URL"
fi
echo "  Registering driver local repo..."
sudo dpkg -i "$DRIVER_DEB"

# 4. CUDA 로컬 리포 다운로드 + 등록
echo "[Step 4] Downloading CUDA 13.0.2 local repo (~4GB)..."
CUDA_DEB="$DL_DIR/cuda-local-repo.deb"
if [ ! -f "$CUDA_DEB" ]; then
    wget -O "$CUDA_DEB" "$CUDA_REPO_URL"
fi
echo "  Registering CUDA local repo..."
sudo dpkg -i "$CUDA_DEB"

# 5. NVLink 스택 개별 패키지 다운로드
echo "[Step 5] Downloading NVLink5 stack packages..."
for URL in "${NVLINK_PKGS[@]}"; do
    FNAME=$(basename "$URL")
    if [ ! -f "$DL_DIR/$FNAME" ]; then
        echo "  Downloading $FNAME..."
        wget -q -O "$DL_DIR/$FNAME" "$URL" || echo "  [WARN] Failed: $FNAME (will try apt later)"
    fi
done

# 6. DOCA 리포지토리 (OFED 용)
echo "[Step 6] Adding NVIDIA DOCA repository..."
curl -fsSL https://www.mellanox.com/downloads/ofed/RPM-GPG-KEY-Mellanox | sudo gpg --dearmor -o /usr/share/keyrings/mellanox-ofed-keyring.gpg 2>/dev/null || true
echo "deb [signed-by=/usr/share/keyrings/mellanox-ofed-keyring.gpg] https://linux.mellanox.com/public/repo/doca/3.2.1/ubuntu24.04/x86_64/ /" | sudo tee /etc/apt/sources.list.d/doca.list

# 7. APT 업데이트
echo "[Step 7] Updating APT cache..."
sudo apt-get update

echo "=============================================="
echo " Repository setup complete!"
echo " Driver local repo: 580.126.20"
echo " CUDA local repo: 13.0.2"
echo " NVLink packages: $DL_DIR/"
echo " DOCA repo: 3.2.1"
echo "=============================================="
