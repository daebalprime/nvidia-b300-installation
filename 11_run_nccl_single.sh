#!/bin/bash
###############################################################################
# 11_run_nccl_single.sh (Array-based Clean Version)
# [단일 노드] NVLink 5세대 성능 최적화 및 행(Hang) 방지 패치 버전
###############################################################################
set -euo pipefail

NUM_GPUS=${1:-8}
BINARY="${HOME}/nccl-workspace/nccl-tests/build/all_reduce_perf"

# 1. 경로 설정
export CUDA_HOME=/usr/local/cuda
export LD_LIBRARY_PATH=${CUDA_HOME}/lib64:/usr/lib/x86_64-linux-gnu:${LD_LIBRARY_PATH:-}

# [A] 디버깅 및 네트워크 소켓 (★싱글 노드 행 방지의 핵심)
export NCCL_DEBUG=INFO
export NCCL_DEBUG_SUBSYS=GRAPH,INIT,ENV
export NCCL_SOCKET_IFNAME=lo                # 싱글노드는 루프백(lo)으로 돌려야 방화벽/라우팅 행을 방지함
export NCCL_TOPO_DUMP_FILE="nccl_topo_single.xml"

# [B] 버퍼 및 네트워크 계층
export NCCL_BUFFSIZE=4194304
export NCCL_IB_AR_THRESHOLD=8192

# [C] Blackwell NVLink 최적화
export NCCL_NVLS_ENABLE=2                   # 2: 지원 안 되거나 실패 시 일반 NVLink로 자동 우회(행 방지)
export NCCL_ALGO=NVLS
export NCCL_PROTO=Simple

# [D] 리소스 제어
export NCCL_MAX_CTAS=32                     # 물리적 채널 상한선에 최적화
export NCCL_MIN_CTAS=16
export NCCL_GRAPH_MIXING_SUPPORT=1

# [E] PCIe 및 통신 레벨 설정
export NCCL_IB_PCI_RELAXED_ORDERING=1
export NCCL_NET_GDR_LEVEL=4
export NCCL_P2P_LEVEL=4

echo "=============================================="
echo " Running Optimized Single Node NCCL Tests"
echo " Bootstrap Socket Interface: ${NCCL_SOCKET_IFNAME}"
echo "=============================================="

# ★옵션 관리 및 주석 처리가 백배 편해지는 배열 구조
MPI_OPTS=(
    -np ${NUM_GPUS}
    --allow-run-as-root
    --bind-to none
    -x LD_LIBRARY_PATH
    -x NCCL_DEBUG
    -x NCCL_DEBUG_SUBSYS
    -x NCCL_SOCKET_IFNAME
    -x NCCL_TOPO_DUMP_FILE
    -x NCCL_BUFFSIZE
    -x NCCL_IB_AR_THRESHOLD
    -x NCCL_NVLS_ENABLE
    -x NCCL_ALGO
    -x NCCL_PROTO
    -x NCCL_MAX_CTAS
    -x NCCL_MIN_CTAS
    -x NCCL_GRAPH_MIXING_SUPPORT
    -x NCCL_IB_PCI_RELAXED_ORDERING
    -x NCCL_NET_GDR_LEVEL
    -x NCCL_P2P_LEVEL
)

# 실행 (백슬래시 없이 깔끔하게 연동)
mpirun "${MPI_OPTS[@]}" ${BINARY} -b 8 -e 8G -f 2 -g 1 -n 20
