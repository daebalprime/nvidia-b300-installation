#!/bin/bash
###############################################################################
# 01_setup_repos.sh (Nuclear Cleanup & Network-Only Mode)
# Removes ALL local repo traces and switches to pure Network + Pinning.
###############################################################################
set -euo pipefail

echo "=============================================="
echo " Nuclear Cleanup & Network-Only Setup"
echo "=============================================="

# 1. 로컬 리포지토리 관련 APT 소스 파일 완전 삭제
echo "[Step 1] Removing local APT source files..."
sudo rm -f /etc/apt/sources.list.d/nvidia-extra-local.list
sudo rm -f /etc/apt/sources.list.d/nvidia-extra-local.list.bak
sudo rm -f /etc/apt/sources.list.d/cuda-*-local*.list
sudo rm -f /etc/apt/sources.list.d/nvidia-driver-local-repo-*.list

# 2. 로컬 디렉토리 삭제
echo "[Step 2] Deleting local repo directories..."
sudo rm -rf /opt/nvidia-pkgs
sudo rm -rf /tmp/nvidia-debs

# 3. 로컬 리포지토리 패키지 자체를 삭제
echo "[Step 3] Purging local repo-installer packages..."
sudo apt-get purge -y "cuda-repo-ubuntu2404-*" "nvidia-driver-local-repo-ubuntu2404-*" || true

# 4. NVIDIA 공식 CUDA 네트워크 리포지토리 등록
echo "[Step 4] Registering official NVIDIA CUDA network repository..."
wget -q https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2404/x86_64/cuda-keyring_1.1-1_all.deb
sudo dpkg -i cuda-keyring_1.1-1_all.deb

# 5. Pinning 패키지 설치
echo "[Step 5] Installing version-locking package..."
sudo apt-get update
sudo apt-get install -y nvidia-driver-pinning-580.126.20

# 6. DOCA 네트워크 리포지토리 등록
echo "[Step 6] Adding DOCA network repository..."
wget -qO - https://linux.mellanox.com/public/repo/doca/3.2.1/ubuntu24.04/x86_64/GPG-KEY-Mellanox.pub | sudo gpg --dearmor -o /usr/share/keyrings/mellanox.gpg --yes
echo "deb [signed-by=/usr/share/keyrings/mellanox.gpg] https://linux.mellanox.com/public/repo/doca/3.2.1/ubuntu24.04/x86_64/ /" | sudo tee /etc/apt/sources.list.d/doca.list

# 7. NVIDIA Container Toolkit 리포지토리 등록
echo "[Step 7] Adding NVIDIA Container Toolkit repository..."
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg --yes
curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
    sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
    sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list

# 8. Docker 공식 리포지토리 등록
echo "[Step 8] Adding official Docker repository..."
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# 9. 최종 업데이트
echo "[Step 9] Final APT update..."
sudo apt-get update

echo "=============================================="
echo " Cleanup Complete! All Network Repos (CUDA, DOCA, Container, Docker) Ready."
echo "=============================================="
