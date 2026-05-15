#!/bin/bash
###############################################################################
# 05_install_container.sh
# [온라인 환경이나 이미지/패키지는 오프라인 방식 유지]
# Docker Engine + NVIDIA Container Toolkit 설치 및 이미지 로드
###############################################################################
set -euo pipefail

# 사전 반입된 이미지가 있는 경로 (기본값: /opt/local-repo/docker-images)
IMAGES_DIR="${1:-/opt/local-repo/docker-images}"

echo "=============================================="
echo " Docker & Container Toolkit Installation"
echo " (Offline Image Loading Mode)"
echo "=============================================="

# 1. Docker Engine 설치
# Note: 패키지 자체는 온라인 리포지토리에서 가져올 수 있으나,
#       사용자가 '들고 들어온다'고 했으므로 local-repo가 설정되어 있어야 합니다.
echo "[Step 1] Installing Docker Engine..."
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

sudo systemctl enable --now docker
sudo usermod -aG docker $USER || true

# 2. NVIDIA Container Toolkit 설치
echo "[Step 2] Installing NVIDIA Container Toolkit..."
sudo apt-get install -y nvidia-container-toolkit

# Docker 런타임 설정 및 CDI 생성 (Blackwell 필수)
echo "  → Configuring Docker runtime and generating CDI..."
sudo nvidia-ctk runtime configure --runtime=docker
sudo nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml
sudo systemctl restart docker

# 3. Docker 이미지 로드 (Rate Limit 대응을 위한 오프라인 로드)
echo "[Step 3] Loading pre-provided Docker images..."
if [ -d "${IMAGES_DIR}" ]; then
    for TAR in "${IMAGES_DIR}"/*.tar; do
        if [ -f "${TAR}" ]; then
            echo "  → Loading: $(basename ${TAR})"
            sudo docker load -i "${TAR}"
        fi
    done
    echo "  [Complete] Image load complete"
else
    echo "  [WARNING] ${IMAGES_DIR} not found. Skipping image load."
    echo "            Please ensure .tar files are in ${IMAGES_DIR}"
fi

# 4. 검증
echo "[Step 4] Verification..."
docker --version
nvidia-container-cli info

echo "=============================================="
echo " Container stack installation complete!"
echo "=============================================="
