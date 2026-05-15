#!/bin/bash
###############################################################################
# 12_run_nccl_multi.sh
# [멀티 노드] Blackwell HGX B300 성능 테스트
###############################################################################
set -euo pipefail

# 사용자 수정 필요
NODE1_IP="172.29.97.136"
NODE2_IP="172.29.97.137"
BINARY="${HOME}/nccl-workspace/nccl-tests/build/all_reduce_perf"

echo "=============================================="
echo " Running NCCL Multi-Node Test"
echo "=============================================="

# Blackwell/ConnectX-8 최적화
export NCCL_IB_ADAPTIVE_ROUTING=1
export NCCL_NET_GDR_LEVEL=5
export NCCL_IB_QPS_PER_CONNECTION=4
export NCCL_IB_GID_INDEX=3
export NCCL_IB_HCA=mlx5

mpirun -np 16 \
    --host ${NODE1_IP}:8,${NODE2_IP}:8 \
    --allow-run-as-root \
    -x LD_LIBRARY_PATH \
    -x NCCL_DEBUG=INFO \
    -x NCCL_IB_ADAPTIVE_ROUTING \
    -x NCCL_NET_GDR_LEVEL \
    -x NCCL_IB_QPS_PER_CONNECTION \
    ${BINARY} -b 8 -e 8G -f 2 -g 1
