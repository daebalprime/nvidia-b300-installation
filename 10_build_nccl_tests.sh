#!/bin/bash
###############################################################################
# 10_build_nccl_tests.sh
# [성능 검증 준비] nccl-tests 다운로드 및 빌드
###############################################################################
set -euo pipefail

WORKSPACE="${HOME}/nccl-workspace"
mkdir -p "${WORKSPACE}"
cd "${WORKSPACE}"

echo "=============================================="
echo " Building NCCL Tests"
echo "=============================================="

# 1. 필수 도구 및 소스 코드 다운로드
echo "[Step 1] Installing build essentials and MPI..."
sudo apt-get install -y git build-essential libopenmpi-dev

if [ ! -d "nccl-tests" ]; then
    echo "[Step 1.1] Cloning nccl-tests repository..."
    git clone https://github.com/NVIDIA/nccl-tests.git
else
    cd nccl-tests && git pull && cd ..
fi

# 2. 빌드 환경 설정
export CUDA_HOME=/usr/local/cuda
if [ ! -d "${CUDA_HOME}" ]; then
    echo "[ERROR] CUDA not found at ${CUDA_HOME}."
    exit 1
fi

# 3. 빌드 실행 (MPI 경로 명시적 지정)
echo "[Step 2] Building NCCL tests..."
cd nccl-tests
make MPI=1 \
     CUDA_HOME=${CUDA_HOME} \
     MPI_HOME=/usr/lib/x86_64-linux-gnu/openmpi \
     -j$(nproc)

echo "=============================================="
echo " Build complete!"
echo " Binary: ${WORKSPACE}/nccl-tests/build/all_reduce_perf"
echo "=============================================="
