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

# 1. 소스 코드 다운로드 (Git)
if [ ! -d "nccl-tests" ]; then
    echo "[Step 1] Cloning nccl-tests repository..."
    git clone https://github.com/NVIDIA/nccl-tests.git
else
    echo "[Step 1] nccl-tests already exists. Pulling latest..."
    cd nccl-tests && git pull && cd ..
fi

# 2. 빌드 환경 설정
export CUDA_HOME=/usr/local/cuda
export MPI_HOME=/usr/local/mpi # DOCA-OFED 설치 시 기본 위치 (버전에 따라 확인 필요)

if [ ! -d "${CUDA_HOME}" ]; then
    echo "[ERROR] CUDA not found at ${CUDA_HOME}. Please run 04_install_gpu_stack.sh first."
    exit 1
fi

# 3. 빌드 실행
echo "[Step 2] Building..."
cd nccl-tests
make MPI=1 \
     CUDA_HOME=${CUDA_HOME} \
     MPI_HOME=${MPI_HOME:-/usr} \
     -j$(nproc)

echo "=============================================="
echo " Build complete!"
echo " Binary: ${WORKSPACE}/nccl-tests/build/all_reduce_perf"
echo "=============================================="
