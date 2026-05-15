#!/bin/bash
###############################################################################
# 11_run_nccl_single.sh
# [단일 노드] Blackwell NVLink5 성능 테스트 (Target: 750GB/s+)
###############################################################################
set -euo pipefail

BINARY="${HOME}/nccl-workspace/nccl-tests/build/all_reduce_perf"

if [ ! -f "${BINARY}" ]; then
    echo "[ERROR] NCCL test binary not found. Please run 10_build_nccl_tests.sh first."
    exit 1
fi

echo "=============================================="
echo " Running NCCL Single Node Test (Blackwell Optimized)"
echo "=============================================="

# Blackwell NVLink5 최적화 변수
export NCCL_IB_ADAPTIVE_ROUTING=1
export NCCL_NET_GDR_LEVEL=5
export NCCL_P2P_LEVEL=5
export NCCL_NVLS_ENABLE=1

# 실행 (8개 GPU 기준)
mpirun -np 8 \
    --allow-run-as-root \
    -x LD_LIBRARY_PATH \
    -x NCCL_DEBUG=INFO \
    -x NCCL_IB_ADAPTIVE_ROUTING \
    -x NCCL_NET_GDR_LEVEL \
    -x NCCL_P2P_LEVEL \
    -x NCCL_NVLS_ENABLE \
    ${BINARY} -b 8 -e 8G -f 2 -g 1
