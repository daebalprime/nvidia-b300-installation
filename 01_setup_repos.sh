#!/bin/bash
###############################################################################
# 01_setup_repos.sh
# 로컬 드라이버 Repo .deb 다운로드 + APT Pin + 네트워크 리포지토리 등록
# 580.126.20 버전 콘크리트 고정
###############################################################################
set -euo pipefail

DRIVER_VERSION="580.126.20"
DRIVER_DEB="nvidia-driver-local-repo-ubuntu2404-${DRIVER_VERSION}_1.0-1_amd64.deb"
DRIVER_URL="https://developer.download.nvidia.com/compute/nvidia-driver/${DRIVER_VERSION}/local_installers/${DRIVER_DEB}"
WORK_DIR="/tmp/nvidia-setup"

echo "=============================================="
echo " Driver ${DRIVER_VERSION} Local Repo + Network Repos Setup"
echo "=============================================="

###############################################################################
# Step 1: 기존 충돌 소스 정리
###############################################################################
echo "[Step 1] Cleaning up ALL existing NVIDIA packages and APT sources..."

# 1a. 설치된 nvidia/cuda 패키지 전체 제거 (버전 충돌 원천 차단)
echo "  → Purging installed nvidia/cuda packages..."
sudo apt-get purge -y "^nvidia-.*" "^libnvidia-.*" "^cuda-.*" "^libnccl.*" 2>/dev/null || true
sudo apt-get autoremove -y 2>/dev/null || true

# 1b. APT 소스 파일 정리
echo "  → Removing old APT source files..."
sudo rm -f /etc/apt/sources.list.d/nvidia-extra-local.list
sudo rm -f /etc/apt/sources.list.d/nvidia-extra-local.list.bak
sudo rm -f /etc/apt/sources.list.d/cuda-*-local*.list
sudo rm -f /etc/apt/sources.list.d/nvidia-driver-local-repo-*.list
sudo rm -f /etc/apt/preferences.d/nvidia-*

# 1c. APT 캐시 완전 초기화 (오염된 메타데이터 제거)
echo "  → Flushing APT cache..."
sudo rm -rf /var/lib/apt/lists/*
sudo apt-get clean

###############################################################################
# Step 2: 580.126.20 로컬 리포지토리 .deb 다운로드 및 설치
###############################################################################
echo "[Step 2] Downloading NVIDIA Driver Local Repo (${DRIVER_VERSION})..."
mkdir -p "${WORK_DIR}"
cd "${WORK_DIR}"

if [ ! -f "${DRIVER_DEB}" ]; then
    wget -q --show-progress "${DRIVER_URL}"
fi

echo "  → Installing local repo package..."
sudo dpkg -i "${DRIVER_DEB}"
sudo cp /var/nvidia-driver-local-repo-ubuntu2404-*/nvidia-driver-local-*-keyring.gpg /usr/share/keyrings/ 2>/dev/null || true

###############################################################################
# Step 3: APT Pin-Priority 1001 (최강 고정 - 다운그레이드까지 강제)
# 로컬 리포지토리의 580.126.20 버전을 절대적으로 우선하도록 강제합니다.
###############################################################################
echo "[Step 3] Creating APT Pin file (Priority 1001)..."
cat <<'EOF' | sudo tee /etc/apt/preferences.d/nvidia-580-pin > /dev/null
# Force ALL nvidia 580 packages to 580.126.20
Package: *nvidia*580*
Pin: version 580.126.20*
Pin-Priority: 1001

Package: libnvidia-*-580
Pin: version 580.126.20*
Pin-Priority: 1001

Package: xserver-xorg-video-nvidia-580
Pin: version 580.126.20*
Pin-Priority: 1001

Package: nvidia-kernel-*-580*
Pin: version 580.126.20*
Pin-Priority: 1001

Package: nvidia-dkms-580*
Pin: version 580.126.20*
Pin-Priority: 1001

Package: nvidia-firmware-580*
Pin: version 580.126.20*
Pin-Priority: 1001

Package: nvidia-fabricmanager*
Pin: version 580.126.20*
Pin-Priority: 1001

Package: nvidia-imex*
Pin: version 580.126.20*
Pin-Priority: 1001

Package: nvlink5*
Pin: version 580.126.20*
Pin-Priority: 1001
EOF

###############################################################################
# Step 4: Container Toolkit 버전 고정 (1.19.0)
###############################################################################
echo "[Step 4] Pinning Container Toolkit to 1.19.0..."
cat <<'EOF' | sudo tee /etc/apt/preferences.d/nvidia-container-toolkit-pin > /dev/null
Package: nvidia-container-toolkit*
Pin: version 1.19.0*
Pin-Priority: 1001

Package: libnvidia-container*
Pin: version 1.19.0*
Pin-Priority: 1001
EOF

###############################################################################
# Step 5: NVIDIA CUDA 네트워크 리포지토리 등록 (CUDA Toolkit 등 추가 패키지용)
###############################################################################
echo "[Step 5] Registering CUDA network repository..."
if [ ! -f cuda-keyring_1.1-1_all.deb ]; then
    wget -q https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2404/x86_64/cuda-keyring_1.1-1_all.deb
fi
sudo dpkg -i cuda-keyring_1.1-1_all.deb

###############################################################################
# Step 6: DOCA 3.2.1 네트워크 리포지토리 등록
###############################################################################
echo "[Step 6] Adding DOCA 3.2.1 repository..."
wget -qO - https://linux.mellanox.com/public/repo/doca/3.2.1/ubuntu24.04/x86_64/GPG-KEY-Mellanox.pub | sudo gpg --dearmor -o /usr/share/keyrings/mellanox.gpg --yes
echo "deb [signed-by=/usr/share/keyrings/mellanox.gpg] https://linux.mellanox.com/public/repo/doca/3.2.1/ubuntu24.04/x86_64/ /" | sudo tee /etc/apt/sources.list.d/doca.list

###############################################################################
# Step 7: Container Toolkit 리포지토리 등록
###############################################################################
echo "[Step 7] Adding NVIDIA Container Toolkit repository..."
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg --yes
curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
    sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
    sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list

###############################################################################
# Step 8: Docker 공식 리포지토리 등록
###############################################################################
echo "[Step 8] Adding Docker repository..."
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

###############################################################################
# Step 9: APT 캐시 갱신 및 Pin 검증
###############################################################################
echo "[Step 9] Final APT update & Pin verification..."
sudo apt-get update

echo ""
echo "--- Pin Verification ---"
apt-cache policy nvidia-driver-580-open 2>/dev/null | head -5 || true
apt-cache policy libnvidia-gl-580 2>/dev/null | head -5 || true
echo ""
echo "=============================================="
echo " Setup Complete! Local Repo + Pin + Network Repos Ready."
echo " Candidate versions should show 580.126.20"
echo "=============================================="
