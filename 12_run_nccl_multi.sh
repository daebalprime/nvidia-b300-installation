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

NODE2_IP="${1:-}"
RESULT_DIR="${2:-/data/nccl-results/multi-node}"
NCCL_BIN="${NCCL_BIN:-/usr/local/nccl-tests/bin}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
HOSTNAME=$(hostname)
RESULT_PREFIX="${RESULT_DIR}/${HOSTNAME}_multi_${TIMESTAMP}"

NUM_GPUS_PER_NODE=8
NUM_NODES=2
TOTAL_GPUS=$((NUM_GPUS_PER_NODE * NUM_NODES))

NODE1_IP=$(hostname -I | awk '{print $1}')

echo "=============================================="
echo " Multi-node NCCL Performance Test"
echo " Node 1: ${NODE1_IP} ($(hostname))"
echo " Node 2: ${NODE2_IP}"
echo " Config:   ${NUM_NODES} Nodes x ${NUM_GPUS_PER_NODE} GPUs = ${TOTAL_GPUS} GPUs"
echo " Results:  ${RESULT_PREFIX}_*.log"
echo "=============================================="

###############################################################################
# 사전 검증
###############################################################################
echo ""
echo "[Pre-verification]"

# 인자 확인
if [ -z "${NODE2_IP}" ]; then
    echo "  [ERROR] Please provide Node 2 IP address."
    echo "  Usage: bash 12_run_nccl_multi.sh <NODE2_IP>"
    echo "  Example: bash 12_run_nccl_multi.sh 10.0.0.2"
    exit 1
fi

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

# SSH 연결 확인
echo "  → Testing SSH connection to Node 2..."
if ! ssh -o BatchMode=yes -o ConnectTimeout=5 "${NODE2_IP}" "hostname" &>/dev/null; then
    echo "  [ERROR] Cannot connect to Node 2 (${NODE2_IP}) via SSH."
    echo ""
    echo "  SSH Key Setup:"
    echo "    ssh-keygen -t ed25519  # Skip if already exists"
    echo "    ssh-copy-id ${NODE2_IP}"
    echo ""
    exit 1
fi
echo "  SSH: $(ssh -o BatchMode=yes ${NODE2_IP} hostname)"

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
cat > "${HOSTFILE}" << EOF
${NODE1_IP} slots=${NUM_GPUS_PER_NODE}
${NODE2_IP} slots=${NUM_GPUS_PER_NODE}
EOF

echo "  Hostfile: ${HOSTFILE}"
cat "${HOSTFILE}"

###############################################################################
# NCCL / MPI 환경 변수
###############################################################################

# NCCL 환경 변수
NCCL_ENV=(
    "-x NCCL_DEBUG=INFO"
    "-x NCCL_DEBUG_SUBSYS=INIT,NET"
    "-x NCCL_IB_DISABLE=0"           # InfiniBand 사용
    "-x NCCL_NET_GDR_LEVEL=5"        # GPUDirect RDMA 레벨 5 (GPU↔NIC 직접 전송)
    "-x NCCL_IB_GID_INDEX=3"         # RoCEv2 사용 시 GID 인덱스 (IB라면 불필요할 수 있음)
    "-x NCCL_IB_TIMEOUT=23"          # IB 재전송 타임아웃 (2^23 × 4.096μs ≈ 34초)
    "-x NCCL_IB_RETRY_CNT=7"         # IB 재전송 최대 횟수
    "-x NCCL_CROSS_NIC=1"            # 여러 NIC 간 교차 통신 허용
    "-x NCCL_SOCKET_IFNAME=^lo,docker" # TCP 소켓에서 루프백/Docker 인터페이스 제외
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
    "--mca btl_tcp_if_exclude lo,docker0"
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
