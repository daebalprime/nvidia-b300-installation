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

# --- Blackwell / InfiniBand 최적화 ---
export NCCL_IB_GID_INDEX=3
export NCCL_IB_ADAPTIVE_ROUTING=1
export NCCL_IB_QPS_PER_CONNECTION=4
export NCCL_NET_GDR_LEVEL=5
export NCCL_DEBUG=INFO

# mpirun 실행 (Node 1에서 실행 기준)
sudo mpirun --allow-run-as-root -np 16 \
    -H localhost:8,${NODE2_IP}:8 \
    -x NCCL_DEBUG=INFO \
    -x NCCL_IB_GID_INDEX \
    -x NCCL_IB_ADAPTIVE_ROUTING \
    -x NCCL_NET_GDR_LEVEL \
    "${BINARY}" -b 1G -e 8G -f 2 -g 1 -n 20

echo "=============================================="
echo " Test Complete!"
echo "=============================================="
