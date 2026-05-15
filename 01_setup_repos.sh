#!/bin/bash
###############################################################################
# 01_setup_repos.sh
# [온라인 환경용] NVIDIA CUDA 및 DOCA 공식 리포지토리 설정
###############################################################################
set -euo pipefail

echo "=============================================="
# 1. 시스템 업데이트 및 필수 도구 설치
echo "[Step 1] Updating system and installing GPG tools..."
sudo apt-get update
sudo apt-get install -y gnupg2 curl ca-certificates

# 2. NVIDIA CUDA 리포지토리 추가 (Ubuntu 24.04)
echo "[Step 2] Adding NVIDIA CUDA repository..."
curl -fsSL https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2404/x86_64/3bf863cc.pub | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-cuda-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/nvidia-cuda-archive-keyring.gpg] https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2404/x86_64/ /" | sudo tee /etc/apt/sources.list.d/cuda-ubuntu2404-x86_64.list

# 3. NVIDIA MLNX/DOCA 리포지토리 추가 (DOCA 3.2.1 기준)
echo "[Step 3] Adding NVIDIA DOCA repository..."
# DOCA GPG Key
curl -fsSL https://www.mellanox.com/downloads/ofed/RPM-GPG-KEY-Mellanox | sudo gpg --dearmor -o /usr/share/keyrings/mellanox-ofed-keyring.gpg
# DOCA Repo (3.2.1 version for Noble)
echo "deb [signed-by=/usr/share/keyrings/mellanox-ofed-keyring.gpg] https://linux.mellanox.com/public/repo/doca/3.2.1/ubuntu24.04/x86_64/ /" | sudo tee /etc/apt/sources.list.d/doca.list

# 4. 리포지토리 업데이트
echo "[Step 4] Updating APT cache with new repositories..."
sudo apt-get update

echo "=============================================="
echo " Repository setup complete!"
echo "=============================================="
