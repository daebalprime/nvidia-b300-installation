#!/bin/bash
###############################################################################
# 00_prepare_docker_images.sh
# [이미지 준비용] Docker Hub에서 이미지를 Pull 하고 .tar로 저장
###############################################################################
set -euo pipefail

# 저장 경로 (05_install_container.sh 에서 참조할 경로)
IMAGES_DIR="/opt/local-repo/docker-images"
mkdir -p "${IMAGES_DIR}"

echo "=============================================="
echo " Docker Image Preparation Tool"
echo "=============================================="

# 1. 이미지 목록 (우리가 사용하는 필수 이미지들)
IMAGES=(
    "prometheuscommunity/ipmi-exporter:latest"
    "prom/node-exporter:latest"
    "prom/prometheus:v3.4.0"
    "nvcr.io/nvidia/k8s/dcgm-exporter:4.5.2-4.8.1-ubuntu22.04"
    "nvidia/cuda:13.0.2-base-ubuntu24.04"
)

# 2. Pull & Save
for IMG in "${IMAGES[@]}"; do
    # 파일명 생성 (특수문자 치환)
    IMG_NAME=$(echo "${IMG}" | tr '/:' '_')
    TAR_PATH="${IMAGES_DIR}/${IMG_NAME}.tar"
    
    echo "  → Processing: ${IMG}"
    if [ -f "${TAR_PATH}" ]; then
        echo "    [SKIP] Already exists."
        continue
    fi

    echo "    → Pulling..."
    sudo docker pull "${IMG}"
    
    echo "    → Saving to ${TAR_PATH}..."
    sudo docker save -o "${TAR_PATH}" "${IMG}"
    echo "    [SUCCESS]"
done

echo "=============================================="
echo " Preparation complete! Images saved in: ${IMAGES_DIR}"
echo "=============================================="
