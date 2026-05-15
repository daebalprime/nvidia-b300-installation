#!/bin/bash
###############################################################################
# 12_run_nccl_multi.sh
# [성능 검증] 멀티 노드 (16 GPU) All-Reduce 테스트
###############################################################################
set -euo pipefail

NODE2_IP="${1:-}"
BINARY="${HOME}/nccl-workspace/nccl-tests/build/all_reduce_perf"

if [ -z "${NODE2_IP}" ]; then
    echo "Usage: $0 <Node2_IP>"
    exit 1
fi

echo "=============================================="
echo " Running Multi-node NCCL All-Reduce (2 Nodes, 16 GPUs)"
echo "=============================================="

# 최적 성능을 위한 환경 변수
export NCCL_IB_GID_INDEX=3
export NCCL_DEBUG=INFO

# mpirun 실행 (Node 1에서 실행 기준)
sudo mpirun --allow-run-as-root -np 16 \
    -H localhost:8,${NODE2_IP}:8 \
    -x NCCL_DEBUG=INFO \
    -x NCCL_IB_GID_INDEX \
    "${BINARY}" -b 8 -e 8G -f 2 -g 1 -n 20

echo "=============================================="
echo " Test Complete!"
echo "=============================================="
