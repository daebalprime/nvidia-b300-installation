#!/bin/bash
###############################################################################
# 04_install_gpu_stack.sh
# Driver 580.126.20 (로컬 Repo + Pin 기반) + CUDA 13.0 + Blackwell 스택
# 사전 조건: 01_setup_repos.sh 실행 완료
###############################################################################
set -euo pipefail

echo "=============================================="
echo " GPU Stack Installation (Version-Locked)"
echo " Driver: 580.126.20 | CUDA: 13.0"
echo "=============================================="

# 사전 검증: APT Pin 파일
if [ ! -f /etc/apt/preferences.d/nvidia-580-pin ]; then
    echo "[ERROR] APT Pin file not found!"
    echo "        Run 01_setup_repos.sh first."
    exit 1
fi

# 사전 검증: Nouveau
if lsmod | grep -q nouveau 2>/dev/null; then
    echo "[ERROR] Nouveau is loaded. Blacklist and reboot first."
    exit 1
fi

# Step 1: 커널 헤더 (현재 구동 커널 전용)
echo "[Step 1] Installing kernel headers for $(uname -r)..."
sudo apt-get install -y linux-headers-$(uname -r)

# Step 2: GPU 드라이버 (Open Kernel - Blackwell 필수)
# Pin-Priority 1001이 580.126.20을 강제하므로 버전 충돌 없음
echo "[Step 2] Installing nvidia-driver-580-open (580.126.20)..."
sudo apt-get install -y --no-install-recommends nvidia-driver-580-open

# Step 3: Blackwell 인프라 스택
echo "[Step 3] Installing Blackwell infrastructure..."
sudo apt-get install -y --no-install-recommends \
    nvidia-fabricmanager \
    nvidia-imex \
    nvlink5 \
    nvlsm

# Step 4: Open Kernel 강제 설정
echo "options nvidia NVreg_OpenRmEnableUnsupportedGpus=1" | \
    sudo tee /etc/modprobe.d/nvidia-open.conf > /dev/null

# Step 5: CUDA Toolkit 13.0
echo "[Step 5] Installing CUDA Toolkit 13.0..."
sudo apt-get install -y cuda-toolkit-13-0

# Step 5.5: CUDA 환경변수 설정 (nvcc 전역 접근 필수)
echo "[Step 5.5] Configuring CUDA environment (PATH + LD_LIBRARY_PATH)..."
cat << 'CUDA_EOF' | sudo tee /etc/profile.d/cuda.sh > /dev/null
export PATH=/usr/local/cuda-13.0/bin${PATH:+:${PATH}}
export LD_LIBRARY_PATH=/usr/local/cuda-13.0/lib64${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}
CUDA_EOF
sudo chmod +x /etc/profile.d/cuda.sh
echo "/usr/local/cuda-13.0/lib64" | sudo tee /etc/ld.so.conf.d/cuda.conf > /dev/null
sudo ldconfig
# 현재 세션에도 즉시 적용
export PATH=/usr/local/cuda-13.0/bin:${PATH}
export LD_LIBRARY_PATH=/usr/local/cuda-13.0/lib64:${LD_LIBRARY_PATH:-}

# Step 6: 부가 패키지
echo "[Step 6] Installing auxiliary packages..."
sudo apt-get install -y libnccl2 libnccl-dev || true
sudo apt-get install -y \
    datacenter-gpu-manager-4-core \
    datacenter-gpu-manager-4-proprietary \
    datacenter-gpu-manager-4-multinode \
    datacenter-gpu-manager-4-multinode-cuda13 || true
sudo apt-get install -y nvidia-gds-13-0 || true

# Step 7: 서비스 활성화
echo "[Step 7] Enabling services..."
sudo systemctl enable --now nvidia-fabricmanager || true
sudo systemctl enable --now nvidia-imex || true

# Step 8: GPUDirect RDMA
echo "[Step 8] Configuring nvidia-peermem..."
sudo modprobe nvidia-peermem || true
echo "nvidia-peermem" | sudo tee /etc/modules-load.d/nvidia-peermem.conf > /dev/null

# Step 9: 검증
echo "[Step 9] Verification..."
echo ""
nvidia-smi || echo "[WARN] nvidia-smi failed - reboot may be required"
echo ""
nvcc --version || echo "[WARN] nvcc not found"
echo ""
echo "--- Installed Driver Version ---"
apt-cache policy nvidia-driver-580-open | head -5
echo ""
echo "=============================================="
echo " Installation Complete!"
echo " sudo reboot to apply driver changes."
echo "=============================================="
