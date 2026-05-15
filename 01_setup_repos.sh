#!/bin/bash
###############################################################################
# 01_setup_repos.sh (The Ultimate Simplified Version)
# No local repos, no manual blocking. Just Network Repo + Official Pinning.
###############################################################################
set -euo pipefail

echo "=============================================="
echo " Modern Version-Locked Setup (via Pinning)"
echo "=============================================="

# 1. NVIDIA 공식 네트워크 리포지토리 등록
echo "[Step 1] Adding official NVIDIA network repository..."
wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2404/x86_64/cuda-keyring_1.1-1_all.deb
sudo dpkg -i cuda-keyring_1.1-1_all.deb
sudo apt-get update

# 2. Pinning 패키지 설치 (이게 핵심: 설치하는 순간 126.20으로 모든 패키지 고정됨)
echo "[Step 2] Installing version-locking package..."
sudo apt-get install -y nvidia-driver-pinning-580.126.20

# 3. DOCA 리포지토리 (네트워크)
echo "[Step 3] Adding DOCA repository..."
wget -qO - https://linux.mellanox.com/public/repo/doca/3.2.1/ubuntu24.04/x86_64/GPG-KEY-Mellanox.pub | sudo gpg --dearmor -o /usr/share/keyrings/mellanox.gpg --yes
echo "deb [signed-by=/usr/share/keyrings/mellanox.gpg] https://linux.mellanox.com/public/repo/doca/3.2.1/ubuntu24.04/x86_64/ /" | sudo tee /etc/apt/sources.list.d/doca.list
sudo apt-get update

echo "=============================================="
echo " Setup Complete. Everything is now locked to 580.126.20."
echo "=============================================="
