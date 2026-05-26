#!/bin/bash
###############################################################################
# 07_verify_all.sh
# [온라인/공통] 전체 시스템 스택 검증 스크립트
###############################################################################
set -euo pipefail

echo "=============================================="
echo " Final System Verification"
echo "=============================================="

# 1. GPU 및 드라이버 확인
echo ""
echo "[1] GPU & Driver Status"
nvidia-smi -L
nvidia-smi topo -m

# 2. Fabric Manager & NVLink Status (Blackwell Optimized)
echo ""
echo "[2] Fabric Manager & NVLink Status"
if systemctl list-unit-files | grep -q nvidia-fabricmanager; then
    if systemctl is-active --quiet nvidia-fabricmanager; then
        echo "  [PASS] Fabric Manager service is active"
    else
        echo "  [FAIL] Fabric Manager service is NOT active"
    fi
else
    echo "  [SKIP] Fabric Manager service is not installed on this system"
fi

# NVLink 연결 상태 상세 확인 (NVL18 등 확인)
NVLINK_STATUS=$(nvidia-smi nvlink -s 2>/dev/null || echo "N/A")
if echo "${NVLINK_STATUS}" | grep -q "Inactive"; then
    echo "  [FAIL] Some NVLinks are Inactive"
    echo "${NVLINK_STATUS}" | grep "Inactive"
elif [ "${NVLINK_STATUS}" == "N/A" ]; then
    echo "  [WARN] Could not retrieve NVLink status"
else
    echo "  [PASS] All NVLinks are Active/Healthy"
fi

# 2.1 IMEX 서비스 확인
echo ""
echo "[2.1] NVIDIA IMEX Status"
if systemctl list-unit-files | grep -q nvidia-imex; then
    if systemctl is-active --quiet nvidia-imex; then
        echo "  [PASS] IMEX service is active"
    else
        echo "  [FAIL] IMEX service is NOT active"
    fi
else
    echo "  [SKIP] IMEX service is not installed on this system"
fi

# 3. 네트워크 (OFED/RDMA) 확인
echo ""
echo "[3] InfiniBand & RDMA Status"
ibstat | grep -E "CA 'mlx5|Link layer|State" || echo "  [WARN] No InfiniBand devices found"

# 4. GPUDirect RDMA (nvidia-peermem) 확인
echo ""
echo "[4] GPUDirect RDMA (nvidia-peermem)"
if lsmod | grep -q nvidia_peermem; then
    echo "  [PASS] nvidia-peermem module is loaded"
else
    echo "  [FAIL] nvidia-peermem module is NOT loaded"
fi

# 5. 컨테이너 런타임 확인
echo ""
echo "[5] Docker & NVIDIA Runtime"
docker version --format '{{.Server.Version}}'
nvidia-container-cli info | head -n 5

# 6. 모니터링 확인
echo ""
echo "[6] Monitoring Exporters"
curl -sf http://localhost:9400/metrics | head -n 1 && echo "  [PASS] DCGM Exporter" || echo "  [FAIL] DCGM Exporter"
curl -sf http://localhost:9100/metrics | head -n 1 && echo "  [PASS] Node Exporter" || echo "  [FAIL] Node Exporter"
curl -sf "http://localhost:9290/ipmi?module=default&target=127.0.0.1" | head -n 1 && echo "  [PASS] IPMI Exporter (Sensors)" || echo "  [FAIL] IPMI Exporter (Sensors)"

echo ""
echo "=============================================="
echo " Verification Complete!"
echo "=============================================="
