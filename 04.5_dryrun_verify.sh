#!/bin/bash
###############################################################################
# 04.5_dryrun_verify.sh
# Pinning 패키지가 580.126.20을 제대로 강제하고 있는지 검증
###############################################################################
set -euo pipefail

TARGET_VERSION="580.126.20"

echo "=============================================="
echo " APT Pinning & Version Verification"
echo "=============================================="

# 1. Pinning 패키지 설치 여부 확인
echo "[Step 1] Checking nvidia-driver-pinning package..."
if dpkg -l | grep -q "nvidia-driver-pinning-580.126.20"; then
    echo "  [PASS] Pinning package is installed."
else
    echo "  [FAIL] Pinning package is NOT installed. Run 04 first."
fi

# 2. APT Policy 검증 (핵심)
echo ""
echo "[Step 2] Verifying APT Priority for 580.126.20..."
# nvidia-driver-580-open 패키지를 예시로 우선순위 확인
POLICY=$(apt-cache policy nvidia-driver-580-open)
echo "${POLICY}"

if echo "${POLICY}" | grep -A 1 "${TARGET_VERSION}" | grep -q "1001"; then
    echo ""
    echo "  [SUCCESS] Version ${TARGET_VERSION} has priority 1001."
    echo "            APT will stick to this version even if newer versions exist."
else
    echo ""
    echo "  [WARNING] Priority 1001 not found for ${TARGET_VERSION}."
    echo "            Version drift might occur."
fi

# 3. 설치 시뮬레이션 (Dry-run)
echo ""
echo "[Step 3] Simulating installation (Dry-run)..."
apt-get install -s nvidia-driver-580-open | grep -E "Inst nvidia-driver-580-open"

echo "=============================================="
echo " Verification Complete"
echo "=============================================="
