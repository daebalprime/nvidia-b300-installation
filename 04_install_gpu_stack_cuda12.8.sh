#!/bin/bash
###############################################################################
# 04_install_gpu_stack_cuda12.8.sh
# Driver 580.126.20 (로컬 Repo + Pin 기반) + CUDA 12.8 + Blackwell 스택
# 사전 조건: 01_setup_repos.sh 실행 완료
###############################################################################
set -euo pipefail

echo "=============================================="
echo " GPU Stack Installation (Version-Locked)"
echo " Driver: 580.126.20 | CUDA: 12.8 (Pyenv 최적화)"
echo "=============================================="

# GPU 아키텍처 선택 (환경 변수 또는 대화형)
GPU_ARCH="${GPU_ARCH:-}"
if [ -z "${GPU_ARCH}" ]; then
    echo "=============================================="
    echo " Select GPU Architecture"
    echo "=============================================="
    echo "  1) Blackwell (B300 / B200)"
    echo "  2) Hopper (H200 NVL / H100)"
    read -p "  Choice (1 or 2): " ARCH_CHOICE
    if [ "${ARCH_CHOICE}" = "1" ]; then
        GPU_ARCH="Blackwell"
    else
        GPU_ARCH="Hopper"
    fi
fi
echo "Using GPU Architecture: ${GPU_ARCH}"

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

# Step 3: GPU 인프라 패키지 구성 및 설치
echo "[Step 3] Configuring GPU infrastructure packages..."
PACKAGES=()

if [ "${GPU_ARCH}" = "Blackwell" ]; then
    echo "  → Configuring Blackwell infrastructure..."
    PACKAGES+=(nvidia-fabricmanager nvidia-imex nvlink5 nvlsm)
else
    echo "  → Configuring Hopper infrastructure..."
    # H200 SXM vs NVL 분기 질문
    FM_REQUIRED="${FM_REQUIRED:-}"
    if [ -z "${FM_REQUIRED}" ]; then
        echo "=============================================="
        echo " Select Hopper Hardware Type"
        echo "=============================================="
        echo "  1) HGX H200 (SXM, NVSwitch 기반) -> Fabric Manager 필수"
        echo "  2) H200 NVL (PCIe, NVLink Bridge) -> Fabric Manager 불필요"
        read -p "  Choice (1 or 2): " FM_CHOICE
        if [ "${FM_CHOICE}" = "1" ]; then
            FM_REQUIRED="true"
        else
            FM_REQUIRED="false"
        fi
    fi
    
    if [ "${FM_REQUIRED}" = "true" ]; then
        echo "  → Fabric Manager will be installed."
        PACKAGES+=(nvidia-fabricmanager)
    else
        echo "  → Skipping Fabric Manager installation (PCIe NVLink Bridge)."
    fi
fi

if [ ${#PACKAGES[@]} -gt 0 ]; then
    echo "  → Installing additional packages: ${PACKAGES[*]}"
    sudo apt-get install -y --no-install-recommends "${PACKAGES[@]}"
else
    echo "  → No additional architecture-specific packages to install."
fi

# Step 4: Open Kernel 강제 설정
echo "options nvidia NVreg_OpenRmEnableUnsupportedGpus=1" | \
    sudo tee /etc/modprobe.d/nvidia-open.conf > /dev/null

# Step 5: CUDA Toolkit 12.8
echo "[Step 5] Installing CUDA Toolkit 12.8..."
sudo apt-get install -y cuda-toolkit-12-8

# Step 5.5: CUDA 환경변수 설정 (nvcc 전역 접근 및 Pyenv/Host 연동)
echo "[Step 5.5] Configuring CUDA environment (PATH + LD_LIBRARY_PATH)..."
cat << 'CUDA_EOF' | sudo tee /etc/profile.d/cuda.sh > /dev/null
export PATH=/usr/local/cuda-12.8/bin${PATH:+:${PATH}}
export LD_LIBRARY_PATH=/usr/local/cuda-12.8/lib64${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}
export CUDA_HOME=/usr/local/cuda-12.8
CUDA_EOF
sudo chmod +x /etc/profile.d/cuda.sh
echo "/usr/local/cuda-12.8/lib64" | sudo tee /etc/ld.so.conf.d/cuda.conf > /dev/null
sudo ldconfig

# 현재 세션에도 즉시 적용
export PATH=/usr/local/cuda-12.8/bin:${PATH}
export LD_LIBRARY_PATH=/usr/local/cuda-12.8/lib64:${LD_LIBRARY_PATH:-}
export CUDA_HOME=/usr/local/cuda-12.8

# Step 6: 부가 패키지
echo "[Step 6] Installing auxiliary packages..."
sudo apt-get install -y libnccl2 libnccl-dev || true
sudo apt-get install -y \
    datacenter-gpu-manager-4-core \
    datacenter-gpu-manager-4-proprietary \
    datacenter-gpu-manager-4-multinode \
    datacenter-gpu-manager-4-multinode-cuda12 || true
sudo apt-get install -y nvidia-gds-12-8 || true

# Step 7: 서비스 활성화
echo "[Step 7] Enabling services..."
if systemctl list-unit-files | grep -q nvidia-fabricmanager; then
    echo "  → Enabling nvidia-fabricmanager..."
    sudo systemctl enable --now nvidia-fabricmanager || true
fi
if systemctl list-unit-files | grep -q nvidia-imex; then
    echo "  → Enabling nvidia-imex..."
    sudo systemctl enable --now nvidia-imex || true
fi

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
echo " CUDA 12.8 GPU Stack Installation Complete!"
echo " sudo reboot to apply driver changes."
echo "=============================================="
