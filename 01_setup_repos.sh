#!/bin/bash
###############################################################################
# 01_setup_repos.sh
# [온라인 환경용] NVIDIA CUDA 로컬 설치 파일(.deb) 다운로드 + DOCA 리포지토리
#
# 전략:
#   네트워크 repo(159.04가 섞이는 원인)를 사용하지 않고,
#   로컬 .deb 인스톨러를 wget으로 받아 로컬 리포지토리로 등록
#   → 오프라인에서 126.20이 깔끔하게 깔렸던 방식 그대로
###############################################################################
set -euo pipefail

# 로컬 인스톨러 URL (NVIDIA 공식)
# CUDA 13.0.2 + Driver 580.126.20 for Ubuntu 24.04
CUDA_LOCAL_DEB_URL="https://developer.download.nvidia.com/compute/cuda/13.0.2/local_installers/cuda-repo-ubuntu2404-13-0-local_13.0.2-580.126.20-1_amd64.deb"
CUDA_LOCAL_DEB="/tmp/cuda-local.deb"

echo "=============================================="
echo " Repository Setup (Local .deb Mode)"
echo "=============================================="

# 1. 시스템 업데이트 및 필수 도구
echo "[Step 1] Updating system and installing tools..."
sudo apt-get update
sudo apt-get install -y gnupg2 curl ca-certificates wget

# 2. 기존 NVIDIA 네트워크 리포 제거 (159.04 오염 방지)
echo "[Step 2] Removing NVIDIA network repo (if exists)..."
sudo rm -f /etc/apt/sources.list.d/cuda-ubuntu2404-x86_64.list

# 3. CUDA 로컬 인스톨러 다운로드
echo "[Step 3] Downloading CUDA local installer..."
echo "  URL: $CUDA_LOCAL_DEB_URL"
echo "  (약 3~4GB, 시간이 걸릴 수 있습니다)"

if [ -f "$CUDA_LOCAL_DEB" ]; then
    echo "  [SKIP] Already downloaded."
else
    wget -O "$CUDA_LOCAL_DEB" "$CUDA_LOCAL_DEB_URL"
fi

# 4. 로컬 리포지토리 등록
echo "[Step 4] Registering local CUDA repository..."
sudo dpkg -i "$CUDA_LOCAL_DEB"

# 5. NVIDIA DOCA 리포지토리 추가 (OFED 용 — 이미 설치됐으면 스킵 가능)
echo "[Step 5] Adding NVIDIA DOCA repository..."
curl -fsSL https://www.mellanox.com/downloads/ofed/RPM-GPG-KEY-Mellanox | sudo gpg --dearmor -o /usr/share/keyrings/mellanox-ofed-keyring.gpg 2>/dev/null || true
echo "deb [signed-by=/usr/share/keyrings/mellanox-ofed-keyring.gpg] https://linux.mellanox.com/public/repo/doca/3.2.1/ubuntu24.04/x86_64/ /" | sudo tee /etc/apt/sources.list.d/doca.list

# 6. APT 캐시 업데이트
echo "[Step 6] Updating APT cache..."
sudo apt-get update

echo "=============================================="
echo " Repository setup complete!"
echo " CUDA local repo → 580.126.20 세트 등록됨"
echo " DOCA repo → 3.2.1 등록됨"
echo "=============================================="
