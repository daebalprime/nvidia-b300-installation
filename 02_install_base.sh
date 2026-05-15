#!/bin/bash
###############################################################################
# 02_install_base.sh
# [온라인 환경용] 기본 도구 및 커널 헤더 설치
###############################################################################
set -euo pipefail

echo "=============================================="
echo " Base System Setup"
echo "=============================================="

# 1. 자동 업데이트 비활성화 (운영 중 예기치 않은 재부팅/업그레이드 방지)
echo "[Step 1] Disabling automatic updates..."
sudo systemctl stop apt-daily.service apt-daily-upgrade.service || true
sudo systemctl disable apt-daily.service apt-daily-upgrade.service || true

# 2. 필수 빌드 도구 및 유틸리티 설치
echo "[Step 2] Installing base utilities..."
sudo apt-get install -y \
    build-essential \
    linux-headers-$(uname -r) \
    jq \
    htop \
    git \
    wget \
    curl \
    vim \
    pciutils \
    ipmitool \
    mstflint \
    perftest \
    dkms

# 3. Nouveau 드라이버 비활성화 (GPU 드라이버 설치 전 필수)
echo "[Step 3] Disabling Nouveau driver..."
if ! grep -q "blacklist nouveau" /etc/modprobe.d/blacklist-nouveau.conf 2>/dev/null; then
    cat <<EOF | sudo tee /etc/modprobe.d/blacklist-nouveau.conf
blacklist nouveau
options nouveau modeset=0
EOF
    sudo update-initramfs -u
    echo "  → Nouveau disabled. A reboot might be required if it was active."
fi

echo "=============================================="
echo " Base installation complete!"
echo "=============================================="
