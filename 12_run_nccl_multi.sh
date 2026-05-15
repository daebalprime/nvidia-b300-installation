#!/bin/bash
###############################################################################
# 12_run_nccl_multi.sh (Blackwell Multi-Node Performance Guide)
# [멀티 노드] NDR(400G) InfiniBand 환경 통신 대역폭 한계치 돌파 튜닝
###############################################################################
set -euo pipefail

# 사용자 설정
HOSTS=${1:-"172.29.97.136,172.29.97.137"}
GPUS_PER_NODE=${2:-8}
TOTAL_GPUS=$(( 2 * GPUS_PER_NODE ))
BINARY="${HOME}/nccl-workspace/nccl-tests/build/all_reduce_perf"

# 1. 경로 및 라이브러리
export CUDA_HOME=/usr/local/cuda
export LD_LIBRARY_PATH=${CUDA_HOME}/lib64:${LD_LIBRARY_PATH:-}

echo "==============================================================================="
echo " Blackwell Multi-Node Benchmark (NDR/ConnectX-7)"
echo " Guide: Syncing NCCL_BUFFSIZE with 4K IB MTU for maximal throughput"
echo "==============================================================================="

# [A] NDR InfiniBand / ConnectX-7 최적화
# 근거: NDR 환경은 IB MTU 4096(4K)이 표준. 큰 버퍼 사용 시 MTU 매칭 필수.
export NCCL_IB_HCA=mlx5                     # 사용할 HCA 명시 (예: =mlx5_0:1,=mlx5_1:1)
export NCCL_IB_TIMEOUT=22                   # 네트워크 규모에 따른 타임아웃 조정 (22: 약 2분)
export NCCL_IB_RETRY_CNT=7                  # 재시도 횟수 (기본 7)
export NCCL_IB_GID_INDEX=3                  # RoCEv2 사용 시 GID 인덱스 (IB는 불필요할 수 있음)
export NCCL_IB_TC=106                       # Traffic Class (QoS 설정 대응)
export NCCL_IB_ADAPTIVE_ROUTING=1           # NDR 스위치의 적응형 라우팅 활용

# [B] 멀티노드 가속 (SHARP & MNNVL)
# 근거: 스위치 단 연산(SHARP)과 멀티노드 NVLink 도메인(IMEX 필요) 활용
export NCCL_COLLNET_ENABLE=1                # SHARP 가속 사용 (1: 필수)
export NCCL_MNNVL_ENABLE=1                  # Multi-Node NVLink 활성화 (2.21+)
export NCCL_NVLS_ENABLE=1                   # NVLink SHARP 사용
export NCCL_ALGO=Tree                       # 멀티노드 병목 시 Tree 알고리즘이 유리

# [C] 하이퍼 튜닝 (대역폭 포화용)
# 근거: 노드 간 NDR 400G/800G 대역폭을 채우기 위해 다중 큐페어(QP) 및 다중 채널 사용
export NCCL_IB_QPS_PER_CONNECTION=4         # 통신당 큐페어 수 증가 (병렬 엔트로피 확보)
export NCCL_MAX_CTAS=64                     # B300 NVLink 18차선 및 NDR 광대역 대응
export NCCL_CROSS_NIC=1                     # NIC 간 부하 분산 최적화
export NCCL_NET_GDR_LEVEL=5                 # GPUDirect RDMA 최대 허용

# [D] 네트워크 안정성 및 디버깅
export NCCL_SOCKET_IFNAME=eth0              # 관리망 인터페이스 고정 (초기화 속도 향상)
export NCCL_TOPO_DUMP_FILE="nccl_topo_multi.xml"

# [실행]
mpirun -np ${TOTAL_GPUS} \
    --host ${HOSTS} \
    --bind-to none \
    --allow-run-as-root \
    -x LD_LIBRARY_PATH \
    -x NCCL_DEBUG=INFO \
    -x NCCL_IB_HCA \
    -x NCCL_IB_TIMEOUT \
    -x NCCL_IB_ADAPTIVE_ROUTING \
    -x NCCL_COLLNET_ENABLE \
    -x NCCL_MNNVL_ENABLE \
    -x NCCL_IB_QPS_PER_CONNECTION \
    -x NCCL_MAX_CTAS \
    -x NCCL_NET_GDR_LEVEL \
    -x NCCL_IB_PCI_RELAXED_ORDERING=1 \
    ${BINARY} -b 8 -e 8G -f 2 -g 1 -n 20
