#!/bin/bash
###############################################################################
# 05_install_container.sh
# [온라인 환경이나 이미지/패키지는 오프라인 방식 유지]
# Docker Engine + NVIDIA Container Toolkit 설치 및 이미지 로드
###############################################################################
set -euo pipefail

# 사전 반입된 이미지가 있는 경로 (기본값: /tmp/nvidia-debs)
IMAGES_DIR="${1:-/tmp/nvidia-debs}"

echo "=============================================="
echo " Docker & Container Toolkit Installation"
echo " (Offline Image Loading Mode)"
echo "=============================================="

# 1. Docker Engine 설치
echo "[Step 1] Installing Docker Engine..."
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

sudo systemctl enable --now docker
sudo usermod -aG docker $USER || true

# 2. NVIDIA Container Toolkit 설치
echo "[Step 2] Installing NVIDIA Container Toolkit..."
# 로컬 리포(01에서 설정한)를 통해 580.126.20과 호환되는 버전을 가져옵니다.
sudo apt-get install -y nvidia-container-toolkit

# Docker 런타임 설정 및 CDI 생성 (Blackwell 필수)
echo "  → Configuring Docker runtime and generating CDI..."
sudo nvidia-ctk runtime configure --runtime=docker
sudo nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml
sudo systemctl restart docker

# 3. Docker 이미지 로드 (Rate Limit 대응을 위한 오프라인 로드)
echo "[Step 3] Loading pre-provided Docker images..."
if [ -d "${IMAGES_DIR}" ]; then
    FOUND_TAR=false
    for TAR in "${IMAGES_DIR}"/*.tar; do
        if [ -f "${TAR}" ]; then
            echo "  → Loading: $(basename ${TAR})"
            sudo docker load -i "${TAR}"
            FOUND_TAR=true
        fi
    done
    if [ "$FOUND_TAR" = true ]; then
        echo "  [Complete] Image load complete"
    else
        echo "  → No .tar images found in ${IMAGES_DIR}"
    fi
else
    echo "  [WARNING] ${IMAGES_DIR} not found. Skipping image load."
fi

# 4. 검증
echo "[Step 4] Verification..."
docker --version
nvidia-container-cli info | head -n 5

echo "=============================================="
echo " Container stack installation complete!"
echo "=============================================="
