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
# OpenMPI 경로는 /usr 를 기본으로 하고, mpicc 위치를 확인
if command -v mpicc >/dev/null; then
    MPI_PATH=$(dirname $(dirname $(which mpicc)))
    export MPI_HOME=${MPI_PATH}
else
    export MPI_HOME=/usr
fi

if [ ! -d "${CUDA_HOME}" ]; then
    echo "[ERROR] CUDA not found at ${CUDA_HOME}. Please run 04_install_gpu_stack.sh first."
    exit 1
fi

# 3. 빌드 실행
echo "[Step 2] Building with MPI_HOME=${MPI_HOME}..."
cd nccl-tests
make MPI=1 \
     CUDA_HOME=${CUDA_HOME} \
     MPI_HOME=${MPI_HOME} \
     -j$(nproc)

echo "=============================================="
echo " Build complete!"
echo " Binary: ${WORKSPACE}/nccl-tests/build/all_reduce_perf"
echo "=============================================="
