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

# 2. Fabric Manager 상태
echo ""
echo "[2] Fabric Manager Status"
systemctl is-active nvidia-fabricmanager

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

echo ""
echo "=============================================="
echo " Verification Complete!"
echo "=============================================="
