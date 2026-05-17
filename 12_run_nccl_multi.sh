#!/bin/bash
###############################################################################
# 12_run_nccl_multi.sh
# [폐쇄망 HGX 서버에서 실행 — Node 1에서 실행]
# 멀티노드 NCCL 성능 테스트 (2노드 × 8GPU = 16GPU)
#
# 목적:
#   1) Inter-node IB 대역폭 실측 → ASTRA-sim BW_INTER 파라미터
#   2) Inter-node 레이턴시 실측 → ASTRA-sim LAT_INTER 파라미터
#   3) SHARP ON/OFF 비교 → SHARP 승수 캘리브레이션
#   4) GPUDirect RDMA 정상 동작 검증
###############################################################################
set -euo pipefail

HOSTS_FILE="${1:-hostnames.txt}"
RESULT_DIR="${2:-/data/nccl-results/multi-node}"
NCCL_BIN="${NCCL_BIN:-/usr/local/nccl-tests/bin}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
HOSTNAME=$(hostname)
RESULT_PREFIX="${RESULT_DIR}/${HOSTNAME}_multi_${TIMESTAMP}"

NUM_GPUS_PER_NODE=8

NODE1_IP=$(hostname -I | awk '{print $1}')

###############################################################################
# 사전 검증 및 호스트 파싱
###############################################################################
echo ""
echo "[Pre-verification & Host Parsing]"

# hosts 파일 확인
if [ ! -f "${HOSTS_FILE}" ]; then
    echo "  [ERROR] Hosts file not found: ${HOSTS_FILE}"
    echo "  Please create '${HOSTS_FILE}' with the list of node IPs (one per line)."
    echo "  Usage: bash 12_run_nccl_multi.sh [hosts_file_path] [result_dir]"
    exit 1
fi

# 주석 및 빈 줄 제외하고 노드 리스트 읽기
NODES=()
while IFS= read -r line || [ -n "$line" ]; do
    line=$(echo "${line}" | sed 's/#.*//' | xargs)
    if [ -n "${line}" ]; then
        NODES+=("${line}")
    fi
done < "${HOSTS_FILE}"

NUM_NODES=${#NODES[@]}
TOTAL_GPUS=$((NUM_GPUS_PER_NODE * NUM_NODES))

if [ "${NUM_NODES}" -lt 2 ]; then
    echo "  [ERROR] At least 2 nodes are required for multi-node testing."
    echo "         Found only ${NUM_NODES} node(s) in ${HOSTS_FILE}."
    exit 1
fi

echo "  Nodes parsed from ${HOSTS_FILE}: ${NODES[*]}"
echo "  Total Target GPUs: ${TOTAL_GPUS} (${NUM_NODES} Nodes x ${NUM_GPUS_PER_NODE} GPUs)"

# 바이너리 확인
if [ ! -f "${NCCL_BIN}/all_reduce_perf" ]; then
    echo "  [ERROR] NCCL Tests binary not found: ${NCCL_BIN}"
    exit 1
fi

# mpirun 확인
if ! command -v mpirun &>/dev/null; then
    echo "  [ERROR] mpirun not found. Please install MPI."
    echo "         apt-get install -y openmpi-bin libopenmpi-dev"
    exit 1
fi

# SSH 연결 확인 (본인 호스트 제외한 타겟 노드 검사)
for node in "${NODES[@]}"; do
    if [ "${node}" != "${NODE1_IP}" ] && [ "${node}" != "127.0.0.1" ] && [ "${node}" != "localhost" ]; then
        echo "  → Testing SSH connection to ${node}..."
        if ! ssh -o BatchMode=yes -o ConnectTimeout=5 "${node}" "hostname" &>/dev/null; then
            echo "  [ERROR] Cannot connect to node ${node} via SSH."
            echo "  Please verify SSH key setup: ssh-copy-id ${node}"
            exit 1
        fi
        echo "    SSH Connection to ${node} OK: $(ssh -o BatchMode=yes ${node} hostname)"
    fi
done

# InfiniBand 확인
echo "  → Checking InfiniBand status..."
ibstat 2>/dev/null | head -5 || echo "  [WARNING] Failed to run ibstat"

mkdir -p "${RESULT_DIR}"
echo "  [Complete] Pre-verification passed"

###############################################################################
# 호스트 파일 생성
###############################################################################
echo ""
echo "[Hostfile Generation]"

HOSTFILE="${RESULT_DIR}/hostfile_${TIMESTAMP}"
rm -f "${HOSTFILE}"
for node in "${NODES[@]}"; do
    echo "${node} slots=${NUM_GPUS_PER_NODE}" >> "${HOSTFILE}"
done

echo "  Hostfile generated: ${HOSTFILE}"
cat "${HOSTFILE}"

###############################################################################
# NCCL / MPI 환경 변수
###############################################################################

# InfiniBand 및 이더넷 인터페이스 명시적 지정 (B300 8-NDR 카드 최적화)
NCCL_IB_HCA="${NCCL_IB_HCA:-mlx5_0,mlx5_10,mlx5_11,mlx5_14,mlx5_15,mlx5_5,mlx5_8,mlx5_9}"
NCCL_SOCKET_IFNAME="${NCCL_SOCKET_IFNAME:-enp138s0f1np1}"

# NCCL 환경 변수 (Blackwell HGX 8-NDR Native IB 최적화)
NCCL_ENV=(
    "-x NCCL_DEBUG=INFO"
    "-x NCCL_DEBUG_SUBSYS=INIT,GRAPH,NET"
    "-x NCCL_IB_DISABLE=0"           # InfiniBand 사용
    "-x NCCL_NET_GDR_LEVEL=3"        # GPUDirect RDMA 레벨 5 (GPU↔NIC 직접 전송)
    "-x NCCL_IB_HCA=${NCCL_IB_HCA}"  # ★ [명시] 데이터 통신에 사용할 8개 NDR 인피니밴드 인터페이스 지정
    "-x NCCL_SOCKET_IFNAME=${NCCL_SOCKET_IFNAME}" # ★ [명시] 핸드셰이크 및 TCP 부트스트랩용 이더넷 인터페이스 지정
    # "-x NCCL_IB_GID_INDEX=3"       # ★ [제거] Native IB 모드에서는 GID Index 지정 시 RoCEv2 오인식 및 성능 급감 유발!
    "-x NCCL_IB_PCI_RELAXED_ORDERING=1" # ★ [추가] CX7/CX8 성능 제한 해제 (PCIe Write 처리 속도 향상)
    "-x NCCL_NET_GDR_READ=1"         # ★ [추가] GPUDirect RDMA 읽기 성능 가속
    "-x NCCL_IB_SPLIT_THRESHOLD=0"   # ★ [추가] 대용량 AllReduce 시 메시지 분할 병목 제거
    "-x NCCL_IB_TIMEOUT=23"          # IB 재전송 타임아웃 (2^23 × 4.096μs ≈ 34초)
    "-x NCCL_IB_RETRY_CNT=7"         # IB 재전송 최대 횟수
    "-x NCCL_CROSS_NIC=0"            # 여러 NIC 간 교차 통신 허용, 켜지마라! 
    "-x NCCL_BUFFSIZE=8388608"       # 통신 버퍼 8MB (대용량 전송 최적화)
    "-x CUDA_VISIBLE_DEVICES=0,1,2,3,4,5,6,7"
    "-x LD_LIBRARY_PATH=/usr/local/cuda-13.0/lib64:/usr/local/cuda/lib64:/usr/lib/x86_64-linux-gnu:\${LD_LIBRARY_PATH:-}"
)

# MPI 공통 옵션
MPI_OPTS=(
    "--hostfile ${HOSTFILE}"
    "-np ${TOTAL_GPUS}"
    "--map-by ppr:${NUM_GPUS_PER_NODE}:node"
    "--bind-to none"
    "--allow-run-as-root"
    "--mca btl_tcp_if_include ${NCCL_SOCKET_IFNAME}" # ★ MPI 통신 네트워크 역시 명시 지정된 이더넷으로 고정
    "--mca pml ob1"
    "--mca btl ^openib"               # UCX/IB 사용 시 btl openib 비활성
)

# 공통 NCCL Tests 파라미터
NCCL_TEST_ARGS="-n 100 -w 20 -c 1 -z 0"
# -n: 반복 횟수 (100회 → 통계적 안정성)
# -w: 워밍업 20회
# -c: correctness check (1=enable)
# -z: 0=no blocking

###############################################################################
# Test 1: AllReduce — SHARP OFF (기본)
###############################################################################
echo ""
echo "=============================================="
echo " [1/4] AllReduce — SHARP OFF"
echo " → Measuring ASTRA-sim BW_INTER, LAT_INTER"
echo "=============================================="
echo ""

LOGFILE="${RESULT_PREFIX}_allreduce_sharp-off.log"

mpirun ${MPI_OPTS[@]} \
    ${NCCL_ENV[@]} \
    -x NCCL_SHARP_DISABLE=1 \
    ${NCCL_BIN}/all_reduce_perf \
    -b 8 -e 8G -f 2 \
    ${NCCL_TEST_ARGS} 2>&1 | tee "${LOGFILE}"

echo ""
echo "  ⭐ BW_INTER (SHARP OFF): Record busbw for 1GB"
echo "  ⭐ LAT_INTER: Record 8B avg time (μs x 1000 -> ns)"
echo "  Results: ${LOGFILE}"

###############################################################################
# Test 2: AllReduce — SHARP ON
###############################################################################
echo ""
echo "=============================================="
echo " [2/4] AllReduce — SHARP ON"
echo " → Measurement for SHARP multiplier back-calculation"
echo "=============================================="
echo ""

LOGFILE="${RESULT_PREFIX}_allreduce_sharp-on.log"

mpirun ${MPI_OPTS[@]} \
    ${NCCL_ENV[@]} \
    -x NCCL_SHARP_DISABLE=0 \
    ${NCCL_BIN}/all_reduce_perf \
    -b 8 -e 8G -f 2 \
    ${NCCL_TEST_ARGS} 2>&1 | tee "${LOGFILE}"

echo ""
echo "  ⭐ BW_INTER (SHARP ON): Record busbw for 1GB"
echo "  ⭐ SHARP Multiplier = BW_ON / BW_OFF -> Input for calibrate_sharp.sh"
echo "  Results: ${LOGFILE}"

###############################################################################
# Test 3: AllReduce 레이턴시 (소량 메시지)
###############################################################################
echo ""
echo "=============================================="
echo " [3/4] AllReduce Precision Latency Measurement"
echo " → Small messages (8B - 64KB)"
echo "=============================================="
echo ""

LOGFILE="${RESULT_PREFIX}_allreduce_latency.log"

mpirun ${MPI_OPTS[@]} \
    ${NCCL_ENV[@]} \
    -x NCCL_SHARP_DISABLE=1 \
    ${NCCL_BIN}/all_reduce_perf \
    -b 8 -e 64K -f 2 \
    ${NCCL_TEST_ARGS} 2>&1 | tee "${LOGFILE}"

echo ""
echo "  Results: ${LOGFILE}"

###############################################################################
# Test 4: 기타 Collective (AllGather, ReduceScatter)
###############################################################################
echo ""
echo "=============================================="
echo " [4/4] AllGather + ReduceScatter"
echo "=============================================="
echo ""

for TEST in all_gather_perf reduce_scatter_perf; do
    TEST_NAME=$(echo ${TEST} | sed 's/_perf//')
    LOGFILE="${RESULT_PREFIX}_${TEST_NAME}.log"

    echo "--- ${TEST_NAME} ---"
    mpirun ${MPI_OPTS[@]} \
        ${NCCL_ENV[@]} \
        -x NCCL_SHARP_DISABLE=1 \
        ${NCCL_BIN}/${TEST} \
        -b 8 -e 8G -f 2 \
        ${NCCL_TEST_ARGS} 2>&1 | tee "${LOGFILE}"

    echo "  Results: ${LOGFILE}"
    echo ""
done

###############################################################################
# 결과 요약
###############################################################################
echo ""
echo "=============================================="
echo " Multi-node NCCL Test Complete!"
echo "=============================================="
echo ""
echo " Result Files:"
ls -la "${RESULT_PREFIX}"_*.log 2>/dev/null
echo ""
echo " ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " ⭐ ASTRA-sim Parameter Extraction Checklist"
echo " ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "   [1] BW_INTER (SHARP OFF):"
echo "       → 1GB busbw (GB/s) from *_allreduce_sharp-off.log"
echo ""
echo "   [2] BW_INTER (SHARP ON):"
echo "       → 1GB busbw (GB/s) from *_allreduce_sharp-on.log"
echo ""
echo "   [3] LAT_INTER:"
echo "       → 8B avg time (μs) x 1000 = ns from *_allreduce_latency.log"
echo ""
echo "   [4] Automatic SHARP Multiplier Calculation:"
echo "       → bash configs/calibrate_sharp.sh"
echo ""
echo " ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo " Additional IB Bandwidth Verification (perftest):"
echo "   Server 1: ib_write_bw -d mlx5_0 -a"
echo "   Server 2: ib_write_bw -d mlx5_0 -a ${NODE1_IP}"
echo ""

# 호스트 파일 정리
rm -f "${HOSTFILE}"
