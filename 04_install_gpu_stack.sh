#!/bin/bash
###############################################################################
# 04_install_gpu_stack.sh
# [온라인 환경용] NVIDIA GPU 스택 설치 (버전 자동 탐지 + 브랜치 격리)
#
# 핵심 전략:
#   1. APT Pinning으로 595 등 다른 브랜치를 완전 차단
#   2. 패키지명에 "-580" 접미사를 명시하여 브랜치 격리
#   3. 리포지토리에서 실제 사용 가능한 580.x 버전을 자동 탐지
###############################################################################
set -euo pipefail

echo "=============================================="
echo " GPU Stack Installation (Branch-Isolated Mode)"
echo "=============================================="

###############################################################################
# Step 0: APT Pinning - 580 브랜치 외 차단
###############################################################################
echo "[Step 0] Setting APT pin to block non-580 packages..."

# 595, 535 등 다른 브랜치가 끼어드는 것을 시스템 레벨에서 차단
cat <<'EOF' | sudo tee /etc/apt/preferences.d/nvidia-branch-lock
# 580 브랜치 패키지에 최고 우선순위 부여
Package: *nvidia*580* *cuda-13-0* *cuda-toolkit-13-0*
Pin: version 580.*
Pin-Priority: 1001

# 그 외 nvidia 패키지는 설치 금지
Package: *nvidia*
Pin: version 595.*
Pin-Priority: -1

Package: *nvidia*
Pin: version 535.*
Pin-Priority: -1
EOF

sudo apt-get update

###############################################################################
# Step 1: 기존 꼬인 패키지 제거
###############################################################################
echo "[Step 1] Purging mismatched NVIDIA packages..."
sudo apt-get purge -y '*nvidia*' '*cuda*' '*fabricmanager*' '*nvlsm*' '*imex*' '*nscq*' || true
sudo apt-get autoremove -y && sudo apt-get autoclean

###############################################################################
# Step 2: 580 브랜치 버전 자동 탐지
###############################################################################
echo "[Step 2] Auto-detecting available 580.x version..."

# nvidia-driver-580-open 기준으로 리포지토리의 580 버전을 탐지
V=$(apt-cache madison nvidia-driver-580-open 2>/dev/null | awk '{print $3}' | grep "^580\." | head -n 1)

if [ -z "$V" ]; then
    echo "[ERROR] No 580.x version found for nvidia-driver-580-open"
    echo "  Check repository configuration (01_setup_repos.sh)"
    exit 1
fi

echo "  → Detected version: $V"

###############################################################################
# Step 3: GPU 드라이버 설치 (Open Kernel - Blackwell 필수)
###############################################################################
echo "[Step 3] Installing NVIDIA Driver ($V)..."
sudo apt-get install -y \
    nvidia-driver-580-open="$V" \
    nvidia-dkms-580-open="$V" \
    nvidia-utils-580="$V" \
    libnvidia-cfg1-580="$V" \
    libnvidia-common-580="$V" \
    libnvidia-compute-580="$V" \
    libnvidia-decode-580="$V" \
    libnvidia-encode-580="$V" \
    libnvidia-fbc1-580="$V" \
    libnvidia-gl-580="$V" \
    nvidia-kernel-source-580-open="$V"

###############################################################################
# Step 4: Fabric Manager 및 NVLink 스택
# 중요: nvidia-imex-580, libnvidia-nscq-580 처럼 -580 접미사 사용!
#        접미사 없는 nvidia-imex를 쓰면 595가 끼어듦
###############################################################################
echo "[Step 4] Installing Fabric Manager & NVLink stack..."

# FM 버전도 동일하게 탐지
FM_V=$(apt-cache madison nvidia-fabricmanager-580 2>/dev/null | awk '{print $3}' | grep "^580\." | head -n 1)
IMEX_V=$(apt-cache madison nvidia-imex-580 2>/dev/null | awk '{print $3}' | grep "^580\." | head -n 1)
NSCQ_V=$(apt-cache madison libnvidia-nscq-580 2>/dev/null | awk '{print $3}' | grep "^580\." | head -n 1)

echo "  → FM version: ${FM_V:-NOT FOUND}"
echo "  → IMEX version: ${IMEX_V:-NOT FOUND}"
echo "  → NSCQ version: ${NSCQ_V:-NOT FOUND}"

# 설치 (버전이 탐지된 경우 고정, 아닌 경우 -580 접미사로 설치)
sudo apt-get install -y \
    nvidia-fabricmanager-580${FM_V:+=$FM_V} \
    nvidia-imex-580${IMEX_V:+=$IMEX_V} \
    libnvidia-nscq-580${NSCQ_V:+=$NSCQ_V} \
    nvlsm \
    libnvsdm \
    mft

sudo systemctl enable --now nvidia-fabricmanager
sudo systemctl enable --now nvidia-imex

###############################################################################
# Step 5: CUDA Toolkit
###############################################################################
echo "[Step 5] Installing CUDA Toolkit 13.0..."
sudo apt-get install -y cuda-toolkit-13-0

###############################################################################
# Step 6: GPUDirect RDMA + 최적화
###############################################################################
echo "[Step 6] Configuring GPUDirect RDMA..."
sudo modprobe nvidia-peermem || true
echo "nvidia-peermem" | sudo tee /etc/modules-load.d/nvidia-peermem.conf > /dev/null
echo "options nvidia NVreg_EnablePCIERelaxedOrderingMode=1" | sudo tee /etc/modprobe.d/nvidia.conf > /dev/null

###############################################################################
# Step 7: 설치 후 버전 일치 검증
###############################################################################
echo ""
echo "=============================================="
echo " Post-install Version Check"
echo "=============================================="
echo ""
dpkg -l | grep -E "nvidia-driver|fabricmanager|imex|nscq" | awk '{printf "  %-40s %s\n", $2, $3}'

# 595 오염 체크
if dpkg -l | grep nvidia | grep -q "595"; then
    echo ""
    echo -e "\e[31m [WARNING] 595 branch packages detected! Check above.\e[0m"
else
    echo ""
    echo -e "\e[32m [OK] No 595 contamination. All packages are 580 branch.\e[0m"
fi

echo ""
echo "=============================================="
echo " GPU Stack Installation Complete"
echo " Please reboot to apply kernel changes."
echo "=============================================="
