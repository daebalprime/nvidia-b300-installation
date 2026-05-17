#!/bin/bash
###############################################################################
# 11_run_nccl_single.sh
# [폐쇄망 HGX 서버에서 실행]
# 단일 노드 NCCL 성능 테스트 (8GPU NVSwitch)
#
# 참고: H200 실제 동작 스크립트 기반으로 B300 NVSwitch에 맞게 최적화
#
# 사전 조건:
#   - 10_build_nccl_tests.sh 완료
#   - GPU 8장 정상 동작 (nvidia-smi 확인)
#   - Fabric Manager 실행 중
#
# 사용법:
#   sudo -E bash 11_run_nccl_single.sh [결과_저장_디렉토리]
###############################################################################
set -euo pipefail

NCCL_BIN="${NCCL_BIN:-/usr/local/nccl-tests/bin}"
RESULT_DIR="${1:-/data/nccl-results/single-node}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
HOSTNAME=$(hostname)
RESULT_PREFIX="${RESULT_DIR}/${HOSTNAME}_${TIMESTAMP}"

# GPU 개수 자동 탐지
NUM_GPUS=$(nvidia-smi --list-gpus 2>/dev/null | wc -l)

# 환경 변수 강제 주입 (sudo 실행 대비)
export CUDA_HOME="${CUDA_HOME:-/usr/local/cuda-13.0}"
export PATH="${CUDA_HOME}/bin:${PATH}"
export LD_LIBRARY_PATH="${CUDA_HOME}/lib64:${LD_LIBRARY_PATH:-}"

echo "=============================================="
echo " Single-node NCCL Performance Test (NVSwitch)"
echo " Host: ${HOSTNAME}"
echo " GPU Count: ${NUM_GPUS}"
echo " Results:  ${RESULT_PREFIX}_*.log"
echo "=============================================="

###############################################################################
# 사전 검증
###############################################################################
echo ""
echo "[Pre-verification]"

if [ ! -f "${NCCL_BIN}/all_reduce_perf" ]; then
    echo "  [ERROR] NCCL Tests binary not found: ${NCCL_BIN}"
    echo "         Please run 10_build_nccl_tests.sh first."
    exit 1
fi

if [ "${NUM_GPUS}" -lt 2 ]; then
    echo "  [ERROR] Less than 2 GPUs detected. At least 2 are required."
    exit 1
fi

# Fabric Manager 확인
if ! systemctl is-active nvidia-fabricmanager &>/dev/null; then
    echo "  [WARNING] Fabric Manager is not running!"
    echo "         sudo systemctl enable --now nvidia-fabricmanager"
fi

# nvidia-peermem 확인
if ! lsmod | grep -q nvidia_peermem; then
    echo "  [WARNING] nvidia_peermem is not loaded."
    echo "         Run: sudo modprobe nvidia-peermem"
fi

mkdir -p "${RESULT_DIR}"
echo "  [Complete] Pre-verification passed"

###############################################################################
# NCCL 환경 변수 (H200 실증 기반 + B300 NVSwitch 최적화)
#
# ★ 핵심 원칙:
#   - H200에서 검증된 설정을 기반으로 함
#   - 싱글 노드: SHARP 비활성, CPU Affinity 무시, NVLS 활성
#   - ALGO, PROTO, P2P_LEVEL 등은 자동 탐지에 맡김
###############################################################################

# 디버그 및 기본 설정
export NCCL_DEBUG=INFO
export NCCL_DEBUG_SUBSYS=INIT,GRAPH,ENV      # 디버깅 정보 대폭 확장 (INIT, ENV 확인)
export NCCL_SOCKET_IFNAME=lo                 # 싱글노드 bootstrap — 루프백

# 성능 & 안정성 (Blackwell / NVSwitch 대응 최적화)
export NCCL_SHARP_DISABLE=1                  # ★ 싱글노드에서 SHARP 비활성 (행 방지)
export NCCL_NVLS_ENABLE=0                    # ★ [중요] NVLink SHARP(NVLS) 비활성화 (Fabric Manager 호환성 및 단일노드 행 해결 1순위)
export NCCL_IB_DISABLE=1                     # ★ [중요] 단일 노드 테스트에서 IB 카드 초기화 강제 방지 (행 방지 2순위)
export NCCL_IGNORE_CPU_AFFINITY=1            # ★ CPU affinity 무시 (mpirun 호환)
export NCCL_SHM_DISABLE=0                    # Shared Memory 활성화
export NCCL_BUFFSIZE=8388608                 # 8MB 버퍼

# P2P 진단용 (만약 하드웨어 NVLink 자체 의심 시, 아래 주석을 풀고 1로 켜서 SM으로만 도는지 점검)
# export NCCL_P2P_DISABLE=0

# MPI 설정 (btl 충돌 방지)
export OMPI_MCA_btl=^openib                  # ★ openib btl 비활성 (UCX 사용)

###############################################################################
# 실행 방식 결정
###############################################################################
# ★ 꿀팁: MPI 통신망이나 소켓 문제로 의심될 경우, 외부에서 `USE_MPI=false`를 주입하여
#         단일 프로세스 멀티스레드 모드(Direct Mode)로 강제 우회 실행이 가능합니다.
#         예: sudo -E USE_MPI=false bash 11_run_nccl_single.sh
USE_MPI="${USE_MPI:-}"
if [ -z "${USE_MPI}" ]; then
    if command -v mpirun &>/dev/null; then
        USE_MPI=true
        echo ""
        echo "  [MPI Mode] mpirun detected → ${NUM_GPUS} processes × 1 GPU each"
    else
        USE_MPI=false
        echo ""
        echo "  [Direct Mode] mpirun not found → single process × ${NUM_GPUS} GPUs"
    fi
else
    echo ""
    echo "  [Forced Mode] USE_MPI forced to ${USE_MPI}"
fi

# MPI 공통 옵션 (H200 레퍼런스 기반)
MPI_OPTS=(
    -np ${NUM_GPUS}
    --allow-run-as-root
    --bind-to none
    --mca btl ^openib
    --mca pml ob1
    -x LD_LIBRARY_PATH
    -x PATH
    -x NCCL_DEBUG
    -x NCCL_DEBUG_SUBSYS
    -x NCCL_SOCKET_IFNAME
    -x NCCL_SHARP_DISABLE
    -x NCCL_NVLS_ENABLE
    -x NCCL_IGNORE_CPU_AFFINITY
    -x NCCL_SHM_DISABLE
    -x NCCL_BUFFSIZE
    -x OMPI_MCA_btl
)

# 테스트 실행 함수
run_test() {
    local BINARY="$1"
    local ARGS="$2"
    local LOGFILE="$3"

    if [ "${USE_MPI}" = true ]; then
        mpirun "${MPI_OPTS[@]}" ${BINARY} ${ARGS} -g 1 2>&1 | tee "${LOGFILE}"
    else
        ${BINARY} ${ARGS} -g ${NUM_GPUS} 2>&1 | tee "${LOGFILE}"
    fi
}

# 공통 테스트 파라미터
COMMON_ARGS="-n 100 -w 20 -c 1 -z 0"

###############################################################################
# Test 1: AllReduce (핵심 — BW_INTRA 측정)
###############################################################################
echo ""
echo "=============================================="
echo " [1/6] AllReduce Bandwidth/Latency Test"
echo " → Measuring ASTRA-sim BW_INTRA, LAT_INTRA"
echo "=============================================="
echo ""

LOGFILE="${RESULT_PREFIX}_allreduce.log"
run_test "${NCCL_BIN}/all_reduce_perf" "-b 8 -e 8G -f 2 ${COMMON_ARGS}" "${LOGFILE}"

echo ""
echo "  ⭐ ASTRA-sim Parameter Extraction Guide:"
echo "     BW_INTRA: busbw value for messages >= 1GB (GB/s)"
echo "     LAT_INTRA: avg time for 8B-4KB messages (us) -> convert to ns"
echo ""
echo "  Results saved: ${LOGFILE}"

###############################################################################
# Test 2: AllReduce 소량 메시지 (레이턴시 정밀 측정)
###############################################################################
echo ""
echo "=============================================="
echo " [2/6] AllReduce Precision Latency Measurement"
echo " → Small messages (8B - 64KB)"
echo "=============================================="
echo ""

LOGFILE="${RESULT_PREFIX}_allreduce_latency.log"
run_test "${NCCL_BIN}/all_reduce_perf" "-b 8 -e 64K -f 2 ${COMMON_ARGS}" "${LOGFILE}"

echo ""
echo "  Results saved: ${LOGFILE}"

###############################################################################
# Test 3: AllGather
###############################################################################
echo ""
echo "=============================================="
echo " [3/6] AllGather Bandwidth Test"
echo "=============================================="
echo ""

LOGFILE="${RESULT_PREFIX}_allgather.log"
run_test "${NCCL_BIN}/all_gather_perf" "-b 8 -e 8G -f 2 ${COMMON_ARGS}" "${LOGFILE}"

echo "  Results saved: ${LOGFILE}"

###############################################################################
# Test 4: ReduceScatter
###############################################################################
echo ""
echo "=============================================="
echo " [4/6] ReduceScatter Bandwidth Test"
echo "=============================================="
echo ""

LOGFILE="${RESULT_PREFIX}_reducescatter.log"
run_test "${NCCL_BIN}/reduce_scatter_perf" "-b 8 -e 8G -f 2 ${COMMON_ARGS}" "${LOGFILE}"

echo "  Results saved: ${LOGFILE}"

###############################################################################
# Test 5: AllToAll
###############################################################################
echo ""
echo "=============================================="
echo " [5/6] AllToAll Bandwidth Test"
echo "=============================================="
echo ""

LOGFILE="${RESULT_PREFIX}_alltoall.log"
run_test "${NCCL_BIN}/alltoall_perf" "-b 8 -e 8G -f 2 ${COMMON_ARGS}" "${LOGFILE}"

echo "  Results saved: ${LOGFILE}"

###############################################################################
# Test 6: SendRecv (P2P 대역폭)
###############################################################################
echo ""
echo "=============================================="
echo " [6/6] SendRecv P2P Bandwidth Test"
echo "=============================================="
echo ""

LOGFILE="${RESULT_PREFIX}_sendrecv.log"
run_test "${NCCL_BIN}/sendrecv_perf" "-b 8 -e 8G -f 2 ${COMMON_ARGS}" "${LOGFILE}"

echo "  Results saved: ${LOGFILE}"

###############################################################################
# 결과 요약
###############################################################################
echo ""
echo "=============================================="
echo " Single-node NCCL Test Complete!"
echo "=============================================="
echo ""
echo " Result Files:"
ls -la "${RESULT_PREFIX}"_*.log 2>/dev/null
echo ""
echo " ⭐ ASTRA-sim Calibration Value Extraction:"
echo "    1) 1GB busbw (GB/s) from AllReduce log -> variables.env BW_INTRA"
echo "    2) 8B avg time (μs x 1000) from AllReduce Latency log -> variables.env LAT_INTRA"
echo ""
echo " Check GPU Topology:"
echo "    nvidia-smi topo -m"
echo ""
echo " Expected NVSwitch B300 Performance:"
echo "    BusBw Target: 750 - 850 GB/s (NV18 full mesh)"
echo ""
echo " Next: 12_run_nccl_multi.sh (Multi-node test)"
echo ""
