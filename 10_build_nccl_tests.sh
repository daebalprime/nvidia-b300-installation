#!/bin/bash
###############################################################################
# 10_build_nccl_tests.sh
# [폐쇄망 HGX 서버에서 실행]
# NCCL Tests 빌드 스크립트
#
# 사전 조건:
#   - 04_install_gpu_stack.sh 완료 (CUDA, libnccl2, libnccl-dev 설치됨)
#   - 06_install_network.sh 완료 (OFED, MPI 설치됨)
#   - nccl-tests 소스가 NCCL_TESTS_SRC에 존재
#
# 사용법:
#   bash 10_build_nccl_tests.sh [nccl-tests 소스 경로]
#   예: bash 10_build_nccl_tests.sh /opt/nccl-tests
###############################################################################
set -euo pipefail

NCCL_TESTS_SRC="${1:-/opt/local-repo/nccl-tests}"
INSTALL_DIR="/usr/local/nccl-tests"

echo "=============================================="
echo " NCCL Tests Build"
echo " Source: ${NCCL_TESTS_SRC}"
echo " Install: ${INSTALL_DIR}"
echo "=============================================="

###############################################################################
# Step 0: 사전 검증
###############################################################################
echo ""
echo "[Step 0] Pre-verification..."

# CUDA 확인
if ! command -v nvcc &>/dev/null; then
    echo "  [ERROR] nvcc not found. Please run 04_install_gpu_stack.sh first."
    exit 1
fi
# CUDA 경로 설정 (13.0 우선)
if [ -d "/usr/local/cuda-13.0" ]; then
    export CUDA_HOME="/usr/local/cuda-13.0"
else
    export CUDA_HOME="${CUDA_HOME:-/usr/local/cuda}"
fi
export PATH="${CUDA_HOME}/bin:${PATH}"
export LD_LIBRARY_PATH="${CUDA_HOME}/lib64:${LD_LIBRARY_PATH:-}"
echo "  CUDA_HOME: ${CUDA_HOME}"
echo "  nvcc: $(nvcc --version 2>/dev/null | tail -1)"

# NCCL 확인
if ! dpkg -l libnccl2 &>/dev/null; then
    echo "  [ERROR] libnccl2 is not installed."
    echo "         apt-get install -y libnccl2 libnccl-dev"
    exit 1
fi
NCCL_VERSION=$(dpkg -l libnccl2 2>/dev/null | grep libnccl2 | awk '{print $3}')
echo "  NCCL Version: ${NCCL_VERSION}"

# MPI 확인 (선택사항이지만 멀티노드에 필요)
MPI_AVAILABLE=false
MPI_FLAGS=""
if command -v mpirun &>/dev/null; then
    MPI_AVAILABLE=true
    MPI_HOME="${MPI_HOME:-/usr}"
    # HPC-X (DOCA-OFED에 포함) 또는 OpenMPI 경로 탐색
    if [ -d "/opt/hpcx" ]; then
        MPI_HOME="/opt/hpcx/ompi"
        echo "  MPI: HPC-X found (${MPI_HOME})"
    elif [ -d "/usr/local/mpi" ]; then
        MPI_HOME="/usr/local/mpi"
        echo "  MPI: OpenMPI (${MPI_HOME})"
    else
        echo "  MPI: System OpenMPI (${MPI_HOME})"
    fi
    MPI_FLAGS="MPI=1 MPI_HOME=${MPI_HOME}"
else
    echo "  [WARNING] MPI not found. Only single-node tests are possible."
    echo "         To enable multi-node tests, install openmpi:"
    echo "         apt-get install -y openmpi-bin libopenmpi-dev"
fi

# nccl-tests 소스 확인
if [ ! -d "${NCCL_TESTS_SRC}" ]; then
    echo ""
    echo "  [ERROR] nccl-tests source not found: ${NCCL_TESTS_SRC}"
    echo ""
    echo "  Download on Seed Machine and copy to the server:"
    echo "    git clone https://github.com/NVIDIA/nccl-tests.git"
    echo "    or"
    echo "    wget https://github.com/NVIDIA/nccl-tests/archive/refs/heads/master.zip"
    echo ""
    echo "  In air-gapped environment:"
    echo "    unzip nccl-tests-master.zip -d /opt/"
    echo "    mv /opt/nccl-tests-master /opt/nccl-tests"
    exit 1
fi

echo "  nccl-tests Source: ${NCCL_TESTS_SRC}"
echo "  [Complete] Pre-verification passed"

###############################################################################
# Step 1: 빌드
###############################################################################
echo ""
echo "[Step 1] Building NCCL Tests..."

cd "${NCCL_TESTS_SRC}"

# 기존 빌드 클린
make clean 2>/dev/null || true

# 빌드 옵션
BUILD_CMD="make -j$(nproc) CUDA_HOME=${CUDA_HOME} NCCL_HOME=/usr"

if [ "${MPI_AVAILABLE}" = true ]; then
    BUILD_CMD="${BUILD_CMD} ${MPI_FLAGS}"
    echo "  → Building with MPI (Single + Multi-node)"
else
    echo "  → Building without MPI (Single-node only)"
fi

echo "  → Build Command: ${BUILD_CMD}"
eval ${BUILD_CMD}

echo "  [Complete] Build successful"

###############################################################################
# Step 2: 설치 (시스템 경로에 복사)
###############################################################################
echo ""
echo "[Step 2] Installing binaries..."

sudo mkdir -p "${INSTALL_DIR}/bin"
sudo cp -v build/* "${INSTALL_DIR}/bin/" 2>/dev/null || true

# PATH에 추가
if ! grep -q "nccl-tests" /etc/profile.d/cuda.sh 2>/dev/null; then
    echo "export PATH=${INSTALL_DIR}/bin:\${PATH}" | \
        sudo tee -a /etc/profile.d/cuda.sh > /dev/null
fi

echo "  [Complete] Binaries installed: ${INSTALL_DIR}/bin/"

###############################################################################
# Step 3: 빌드 검증
###############################################################################
echo ""
echo "[Step 3] Verifying build results..."

echo ""
echo "  --- Generated Binaries ---"
ls -la "${INSTALL_DIR}/bin/" 2>/dev/null

TESTS=(
    "all_reduce_perf"
    "all_gather_perf"
    "broadcast_perf"
    "reduce_scatter_perf"
    "reduce_perf"
    "alltoall_perf"
    "scatter_perf"
    "gather_perf"
    "sendrecv_perf"
    "hypercube_perf"
)

echo ""
echo "  --- Binary Verification ---"
FOUND=0
MISSING=0
for TEST in "${TESTS[@]}"; do
    if [ -f "${INSTALL_DIR}/bin/${TEST}" ]; then
        printf "  %-30s [OK]\n" "${TEST}"
        FOUND=$((FOUND + 1))
    else
        printf "  %-30s [MISSING]\n" "${TEST}"
        MISSING=$((MISSING + 1))
    fi
done

echo ""
echo "  Build complete: ${FOUND} successful, ${MISSING} missing"

###############################################################################
# 완료 요약
###############################################################################
echo ""
echo "=============================================="
echo " NCCL Tests Build Complete!"
echo "=============================================="
echo ""
echo " Binary location: ${INSTALL_DIR}/bin/"
echo ""
echo " Next Steps:"
echo "   1) Single-node test:  bash 11_run_nccl_single.sh"
echo "   2) Multi-node test:   bash 12_run_nccl_multi.sh"
echo ""
echo " Quick test (2 GPUs):"
echo "   ${INSTALL_DIR}/bin/all_reduce_perf -b 8 -e 256M -f 2 -g 2"
echo ""
