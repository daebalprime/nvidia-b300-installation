#!/bin/bash
###############################################################################
# install_cuda12.8_only.sh
# [온라인 환경용] 드라이버 변경 없이 CUDA 12.8 Toolkit만 단독 설치하는 스크립트
#
# 기존의 NVIDIA 드라이버(580.x 등) 및 NVLink 인프라가 구축된 상태에서,
# 시스템 서비스 중단이나 재부팅 없이 CUDA 12.8 Toolkit만 깔끔하게 추가 설치합니다.
###############################################################################
set -euo pipefail

echo "=============================================="
echo " CUDA 12.8 Toolkit Standalone Installer"
echo "=============================================="

# Step 1: CUDA 네트워크 리포지토리 확인 및 등록
echo "[Step 1] Verifying CUDA network repository..."
if [ ! -f /etc/apt/sources.list.d/cuda-ubuntu2404-x86_64.list ] && [ ! -f /etc/apt/sources.list.d/cuda.list ]; then
    echo "  → Registering CUDA keyring..."
    mkdir -p /tmp/cuda-keyring
    cd /tmp/cuda-keyring
    wget -q https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2404/x86_64/cuda-keyring_1.1-1_all.deb
    sudo dpkg -i cuda-keyring_1.1-1_all.deb
    cd - > /dev/null
fi

echo "  → Updating APT package cache..."
sudo apt-get update

# Step 2: CUDA 12.8 Toolkit 단독 설치
# 드라이버 패키지를 건드리지 않고 컴파일러(nvcc) 및 개발 툴킷만 설치합니다.
echo "[Step 2] Installing CUDA 12.8 Toolkit..."
sudo apt-get install -y --no-install-recommends cuda-toolkit-12-8

# Step 3: 부가 패키지 (NCCL, GDS 12.8) 추가 설치
echo "[Step 3] Installing CUDA 12.8 compatible auxiliary libraries..."
sudo apt-get install -y --no-install-recommends \
    libnccl2 \
    libnccl-dev \
    nvidia-gds-12-8 || true

# Step 4: 환경변수 설정 (/etc/profile.d/cuda.sh 업데이트)
echo "[Step 4] Configuring system-wide CUDA 12.8 environment variables..."
cat << 'CUDA_EOF' | sudo tee /etc/profile.d/cuda.sh > /dev/null
export PATH=/usr/local/cuda-12.8/bin${PATH:+:${PATH}}
export LD_LIBRARY_PATH=/usr/local/cuda-12.8/lib64${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}
export CUDA_HOME=/usr/local/cuda-12.8
CUDA_EOF
sudo chmod +x /etc/profile.d/cuda.sh

# Dynamic linker cache 갱신
echo "/usr/local/cuda-12.8/lib64" | sudo tee /etc/ld.so.conf.d/cuda-12.8.conf > /dev/null
sudo ldconfig

# 현재 세션 적용
export PATH=/usr/local/cuda-12.8/bin:${PATH}
export LD_LIBRARY_PATH=/usr/local/cuda-12.8/lib64:${LD_LIBRARY_PATH:-}
export CUDA_HOME=/usr/local/cuda-12.8

# Step 5: 검증
echo "[Step 5] Verifying installation..."
echo ""
if command -v nvcc &>/dev/null; then
    echo "  [SUCCESS] nvcc is successfully configured:"
    nvcc --version
else
    echo "  [ERROR] nvcc not found in PATH."
fi
echo ""
echo "=============================================="
echo " CUDA 12.8 Installation Complete! (No reboot required)"
echo " Please run: source /etc/profile.d/cuda.sh"
echo "=============================================="
