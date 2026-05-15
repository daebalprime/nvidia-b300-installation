#!/bin/bash
###############################################################################
# 11_run_nccl_single.sh
# [성능 검증] 단일 노드 (8 GPU) All-Reduce 테스트
# 타겟: BusBw 750~850 GB/s
###############################################################################
set -euo pipefail

BINARY="${HOME}/nccl-workspace/nccl-tests/build/all_reduce_perf"

if [ ! -f "${BINARY}" ]; then
    echo "[ERROR] NCCL binary not found. Please run 10_build_nccl_tests.sh first."
    exit 1
fi

echo "=============================================="
echo " Running Single-node NCCL All-Reduce"
echo " Target: BusBw > 750 GB/s (Blackwell Standard)"
echo "=============================================="

# 최적 성능을 위한 환경 변수
export NCCL_IB_GID_INDEX=3
export NCCL_IB_HCA=^mlx5_bond_0 # 필요 시 조정
export NCCL_DEBUG=INFO

sudo mpirun --allow-run-as-root -np 8 \
    -H localhost:8 \
    -x NCCL_DEBUG=INFO \
    -x NCCL_IB_GID_INDEX \
    "${BINARY}" -b 8 -e 8G -f 2 -g 1 -n 20

echo "=============================================="
echo " Test Complete!"
echo "=============================================="
