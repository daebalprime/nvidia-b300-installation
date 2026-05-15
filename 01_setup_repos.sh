#!/bin/bash
###############################################################################
# 01_setup_repos.sh (Optimized & Simplified)
# Use NVIDIA's official pinning package to lock 580.126.20
###############################################################################
set -euo pipefail

DRIVER_VERSION="580.126.20"
CUDA_VERSION="13.0.2"
DCGM_VERSION="4.5.3-1"

DL_DIR="/tmp/nvidia-debs"
EXTRA_REPO="/opt/nvidia-pkgs"
mkdir -p "$DL_DIR" "$EXTRA_REPO"

echo "=============================================="
echo " Simplified Setup using NVIDIA Pinning Package"
echo "=============================================="

# 1. Prerequisites
sudo apt-get update || true
sudo apt-get install -y wget dpkg-dev

# 2. Local Repo Installers (Layer 1 & 2)
# Driver Local Repo
DRIVER_DEB="${DL_DIR}/nvidia-driver-local-repo-ubuntu2404-${DRIVER_VERSION}_1.0-1_amd64.deb"
wget -c -O "$DRIVER_DEB" "https://developer.download.nvidia.com/compute/nvidia-driver/${DRIVER_VERSION}/local_installers/nvidia-driver-local-repo-ubuntu2404-${DRIVER_VERSION}_1.0-1_amd64.deb"
sudo dpkg -i "$DRIVER_DEB"

# CUDA Local Repo
CUDA_DEB="${DL_DIR}/cuda-repo-ubuntu2404-13-0-local_${CUDA_VERSION}-580.95.05-1_amd64.deb"
wget -c -O "$CUDA_DEB" "https://developer.download.nvidia.com/compute/cuda/${CUDA_VERSION}/local_installers/cuda-repo-ubuntu2404-13-0-local_${CUDA_VERSION}-580.95.05-1_amd64.deb"
sudo dpkg -i "$CUDA_DEB"

# 3. Layer 3: Extra Packages (Including the Official Pinning Package)
NVIDIA_REPO="https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2404/x86_64"
EXTRA_PKGS=(
    "nvidia-driver-pinning-580.126.20_580.126.20-1_amd64.deb" # 이 녀석이 핵심입니다
    "nvidia-fabricmanager_${DRIVER_VERSION}-1_amd64.deb"
    "nvidia-imex_${DRIVER_VERSION}-1_amd64.deb"
    "nvlink5-580_${DRIVER_VERSION}-1_amd64.deb"
    "datacenter-gpu-manager-4-core_${DCGM_VERSION}_amd64.deb"
    "datacenter-gpu-manager-4-cuda13_${DCGM_VERSION}_amd64.deb"
    "datacenter-gpu-manager-4-multinode_${DCGM_VERSION}_amd64.deb"
    "datacenter-gpu-manager-4-multinode-cuda13_${DCGM_VERSION}_amd64.deb"
)

for PKG in "${EXTRA_PKGS[@]}"; do
    wget -c -q -O "${EXTRA_REPO}/${PKG}" "${NVIDIA_REPO}/${PKG}" || true
done

# Index and Register
cd "${EXTRA_REPO}"
dpkg-scanpackages . /dev/null > Packages
gzip -9c Packages > Packages.gz
echo "deb [trusted=yes] file:${EXTRA_REPO} /" | sudo tee /etc/apt/sources.list.d/nvidia-extra-local.list

# 4. Cleanup & Update
sudo apt-get update

echo "=============================================="
echo " Setup Complete. Now run 04_install_gpu_stack.sh"
echo "=============================================="
