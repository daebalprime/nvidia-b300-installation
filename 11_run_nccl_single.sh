#!/bin/bash
###############################################################################
# 11_run_nccl_single.sh (Blackwell B300 Performance Optimization Guide)
# [단일 노드] NVLink 5세대(1.8TB/s) 성능 극대화 튜닝 스크립트
###############################################################################
set -euo pipefail

NUM_GPUS=${1:-8}
BINARY="${HOME}/nccl-workspace/nccl-tests/build/all_reduce_perf"

# 1. 경로 설정
export CUDA_HOME=/usr/local/cuda
export LD_LIBRARY_PATH=${CUDA_HOME}/lib64:/usr/lib/x86_64-linux-gnu:${LD_LIBRARY_PATH:-}

echo "==============================================================================="
echo " Blackwell HGX B300 NCCL Optimization (Intra-Node)"
echo " Rationale: High-bandwidth (1.8TB/s) NVLink5 saturation with 18-lane utilization"
echo "==============================================================================="

# [A] 디버깅 및 토폴로지 분석
export NCCL_DEBUG=INFO                      # VERSION, WARN, INFO, TRACE
export NCCL_DEBUG_SUBSYS=GRAPH,INIT,ENV     # 특정 서브시스템 로그 필터링
export NCCL_TOPO_DUMP_FILE="nccl_topo_single.xml"

# [B] 버퍼 및 네트워크 계층 (MTU 상관관계 반영)
# 근거: NCCL 버퍼와 하드웨어 MTU(NDR 기준 4K)를 동기화하여 패킷 단편화 오버헤드 방지
export NCCL_BUFFSIZE=4194304                # (Default: 4MB) 대형 메시지 처리용 그릇
export NCCL_IB_AR_THRESHOLD=8192            # Adaptive Routing 적용 임계값 (Default: 8K)

# [C] Blackwell 전용 NVLink SHARP(NVLS) 최적화
# 근거: 3세대 NVSwitch(Blackwell)의 하드웨어 연산 오프로딩 활용
export NCCL_NVLS_ENABLE=1                   # 1: 필수 활성화, 2: 자동(실패 시 Fallback)
export NCCL_ALGO=NVLS                       # NVLS, RING, TREE (Blackwell은 NVLS 최우선)
export NCCL_PROTO=Simple                    # Simple, LL, LL128 (LL은 지연시간 위주)

# [D] 리소스/병렬화 채널 튜닝 (B300 18차선 대응)
# 근거: GPU당 18개 NVLink 레인을 100% 활용하기 위해 채널 수를 32~64개로 확장
# 1개 채널 = 1개 SM 그룹 점유. 대역폭 포화(Saturation)를 위해 병렬 통신 스레드 확보 필수.
export NCCL_MAX_CTAS=64                     # (구 NCCL_MAX_NCHANNELS) 대역폭 한계치 돌파용
export NCCL_MIN_CTAS=16                     # (구 NCCL_MIN_NCHANNELS) 소량 데이터 지연시간 확보용
export NCCL_GRAPH_MIXING_SUPPORT=1          # 병렬 CUDA Graph 지원

# [E] PCIe 및 통신 레벨 설정
export NCCL_IB_PCI_RELAXED_ORDERING=1       # PCIe 전송 효율 극대화 (1: 강제 활성)
export NCCL_NET_GDR_LEVEL=5                 # GDR 경로 거리 (5: SYS, 최대로 허용)
export NCCL_P2P_LEVEL=5                     # P2P 통신 허용 범위 (5: SYS)

# [실행]
# --bind-to none: MPI 프로세스가 특정 코어에 묶여 NCCL 스레드 성능을 저하시키는 현상 방지
mpirun -np ${NUM_GPUS} \
    --allow-run-as-root \
    --bind-to none \
    -x LD_LIBRARY_PATH \
    -x NCCL_DEBUG \
    -x NCCL_DEBUG_SUBSYS \
    -x NCCL_NVLS_ENABLE \
    -x NCCL_ALGO \
    -x NCCL_PROTO \
    -x NCCL_BUFFSIZE \
    -x NCCL_MAX_CTAS \
    -x NCCL_MIN_CTAS \
    -x NCCL_IB_PCI_RELAXED_ORDERING \
    -x NCCL_NET_GDR_LEVEL \
    -x NCCL_P2P_LEVEL \
    ${BINARY} -b 8 -e 8G -f 2 -g 1 -n 20
