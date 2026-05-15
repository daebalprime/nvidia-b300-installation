#!/bin/bash
###############################################################################
# 01_setup_repos.sh
# [온라인 환경용] NVIDIA 로컬 리포지토리 .deb 다운로드 + 등록
###############################################################################
set -euo pipefail

DRIVER_VERSION="580.126.20"
CUDA_VERSION="13.0.2"
CUDA_DRIVER_VERSION="580.95.05"
DCGM_VERSION="4.5.3-1"

DL_DIR="/tmp/nvidia-debs"
EXTRA_REPO="/opt/nvidia-pkgs"

echo "=============================================="
echo " Repository Setup (Clean & Precise)"
echo "=============================================="

# 0. 디렉토리 정리 및 초기화
echo "[Step 0] Initializing directory..."
sudo mkdir -p "$DL_DIR" "$EXTRA_REPO"
# 찌꺼기 제거 후, apt update 에러 방지를 위해 빈 인덱스 즉시 생성
sudo rm -rf "${EXTRA_REPO}"/*
touch "${EXTRA_REPO}/Packages"
gzip -c "${EXTRA_REPO}/Packages" > "${EXTRA_REPO}/Packages.gz"

# 1. 필수 도구 설치
echo "[Step 1] Installing prerequisites..."
# 로컬 리포 에러를 무시하고 넘어가기 위해 --allow-releaseinfo-change 등 사용 가능하나,
# 여기서는 단순히 update 실패를 무시하고 필요한 도구만 설치 시도
sudo apt-get update || true
sudo apt-get install -y gnupg2 curl ca-certificates wget dpkg-dev

# 2. Layer 1: GPU Driver Local Repo
DRIVER_DEB="${DL_DIR}/nvidia-driver-local-repo-ubuntu2404-${DRIVER_VERSION}_1.0-1_amd64.deb"
DRIVER_URL="https://developer.download.nvidia.com/compute/nvidia-driver/${DRIVER_VERSION}/local_installers/nvidia-driver-local-repo-ubuntu2404-${DRIVER_VERSION}_1.0-1_amd64.deb"

echo "[Step 2] Layer 1: GPU Driver Local Repo..."
if [ ! -s "$DRIVER_DEB" ]; then
    wget -c -O "$DRIVER_DEB" "$DRIVER_URL" || { rm -f "$DRIVER_DEB"; exit 1; }
fi
sudo dpkg -i "$DRIVER_DEB"
sudo cp /var/nvidia-driver-local-repo-ubuntu2404-*/nvidia-driver-local-*-keyring.gpg /usr/share/keyrings/ 2>/dev/null || true

# 3. Layer 2: CUDA Toolkit Local Repo
CUDA_DEB="${DL_DIR}/cuda-repo-ubuntu2404-13-0-local_${CUDA_VERSION}-${CUDA_DRIVER_VERSION}-1_amd64.deb"
CUDA_URL="https://developer.download.nvidia.com/compute/cuda/${CUDA_VERSION}/local_installers/cuda-repo-ubuntu2404-13-0-local_${CUDA_VERSION}-${CUDA_DRIVER_VERSION}-1_amd64.deb"

echo "[Step 3] Layer 2: CUDA Local Repo..."
if [ ! -s "$CUDA_DEB" ]; then
    wget -c -O "$CUDA_DEB" "$CUDA_URL" || { rm -f "$CUDA_DEB"; exit 1; }
fi
sudo dpkg -i "$CUDA_DEB"
sudo cp /var/cuda-repo-ubuntu2404-13-0-local/cuda-*-keyring.gpg /usr/share/keyrings/ 2>/dev/null || true

# 4. Layer 3: 개별 패키지 다운로드
echo "[Step 4] Layer 3: Downloading extra Blackwell packages..."
NVIDIA_REPO="https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2404/x86_64"
EXTRA_PKGS=(
    "nvidia-fabricmanager_${DRIVER_VERSION}-1_amd64.deb"
    "nvidia-fabricmanager-dev_${DRIVER_VERSION}-1_amd64.deb"
    "nvidia-imex_${DRIVER_VERSION}-1_amd64.deb"
    "libnvidia-nscq_${DRIVER_VERSION}-1_amd64.deb"
    "libnvsdm_${DRIVER_VERSION}-1_amd64.deb"
    "nvlink5-580_${DRIVER_VERSION}-1_amd64.deb"
    "nvlink5_${DRIVER_VERSION}-1_amd64.deb"
    "datacenter-gpu-manager-4-core_${DCGM_VERSION}_amd64.deb"
    "datacenter-gpu-manager-4-cuda13_${DCGM_VERSION}_amd64.deb"
    "datacenter-gpu-manager-4-multinode-cuda13_${DCGM_VERSION}_amd64.deb"
)

for PKG in "${EXTRA_PKGS[@]}"; do
    TARGET="${EXTRA_REPO}/${PKG}"
    echo "  → Downloading ${PKG}..."
    if ! wget -c -q -O "$TARGET" "${NVIDIA_REPO}/${PKG}"; then
        echo "  [ERROR] Failed to download: ${PKG}"
        rm -f "$TARGET"
        exit 1
    fi
done

echo "  → Generating real package index..."
cd "${EXTRA_REPO}"
dpkg-scanpackages . /dev/null > Packages
gzip -9c Packages > Packages.gz

# 5. 모든 NVIDIA 네트워크 소스 제거
echo "[Step 5] Blocking network sources..."
for f in /etc/apt/sources.list.d/cuda*.list /etc/apt/sources.list.d/cuda*.sources; do
    [ -f "$f" ] || continue
    if grep -q "developer.download.nvidia.com" "$f" 2>/dev/null; then
        sudo rm -f "$f"
    fi
done

# 6. Layer 3 APT 소스 등록 (이미 있으면 덮어씀)
echo "[Step 6] Registering Layer 3 local repo..."
echo "deb [trusted=yes] file:${EXTRA_REPO} /" | sudo tee /etc/apt/sources.list.d/nvidia-extra-local.list > /dev/null

# 7. 로컬 소스 강제 신뢰 설정
sudo sed -i 's/deb file/deb [trusted=yes] file/g' /etc/apt/sources.list.d/cuda*.list 2>/dev/null || true
sudo sed -i 's/deb file/deb [trusted=yes] file/g' /etc/apt/sources.list.d/nvidia*.list 2>/dev/null || true

# 8. DOCA 리포지토리
echo "[Step 8] Adding DOCA repository..."
wget -qO - --no-check-certificate https://linux.mellanox.com/public/repo/doca/3.2.1/ubuntu24.04/x86_64/GPG-KEY-Mellanox.pub 2>/dev/null | \
    sudo gpg --dearmor -o /usr/share/keyrings/mellanox.gpg --yes || true
echo "deb [signed-by=/usr/share/keyrings/mellanox.gpg] https://linux.mellanox.com/public/repo/doca/3.2.1/ubuntu24.04/x86_64/ /" | \
    sudo tee /etc/apt/sources.list.d/doca.list

# 9. 최종 APT 캐시 업데이트 (여기서 모든 로컬 패키지가 인식됨)
echo "[Step 9] Final APT update..."
sudo apt-get update

echo "=============================================="
echo " Setup complete! DCGM 4.5.3-1 and 580.126.20 ready."
echo "=============================================="
