#!/bin/bash
###############################################################################
# 04.5_dryrun_verify.sh
# [사전 검증] 실제 설치 전 리포지토리 패키지 가용성 및 버전 일치 확인
###############################################################################
set -u

# 타겟 버전 (안정적인 580.126.20 버전)
V="580.126.20-0ubuntu0.24.04.1"

echo "=============================================="
echo " Pre-flight Version Verification (Dry-run)"
echo " Target Version: $V"
echo "=============================================="

PACKAGES=(
    "nvidia-driver-580-open"
    "nvidia-dkms-580-open"
    "nvidia-fabricmanager-580"
)

FAILED=0

echo "[Step 1] Checking package availability in Repository..."
for PKG in "${PACKAGES[@]}"; do
    printf "  Checking %-25s : " "$PKG"
    if apt-cache madison "$PKG" | grep -q "$V"; then
        echo -e "\e[32m[MATCH]\e[0m"
    else
        echo -e "\e[31m[NOT FOUND]\e[0m"
        AVAILABLE=$(apt-cache madison "$PKG" | head -n 1 | awk '{print $3}')
        echo "    → Available latest: $AVAILABLE"
        FAILED=1
    fi
done

echo ""
echo "[Step 2] Simulating Installation (Dependency Check)..."
if [ $FAILED -eq 0 ]; then
    if sudo apt-get install -s \
        nvidia-driver-580-open=$V \
        nvidia-dkms-580-open=$V \
        nvidia-fabricmanager-580=$V > /dev/null 2>&1; then
        echo -e "\e[32m  [PASS] All packages are consistent and ready for installation.\e[0m"
    else
        echo -e "\e[31m  [FAIL] Dependency conflict detected even though versions exist.\e[0m"
        FAILED=1
    fi
else
    echo -e "\e[33m  [SKIP] Skipping simulation due to missing package versions.\e[0m"
fi

echo "=============================================="
if [ $FAILED -eq 0 ]; then
    echo -e "\e[32m CONCLUSION: SAFE TO PROCEED WITH 04_install_gpu_stack.sh\e[0m"
else
    echo -e "\e[31m CONCLUSION: STOP! Fix version mismatches before installation.\e[0m"
fi
echo "=============================================="

exit $FAILED
