#!/bin/bash
###############################################################################
# 04.5_dryrun_verify.sh
# [사전 검증] 실제 설치 전 리포지토리 패키지 가용성 및 버전 일치 확인
###############################################################################
set -u

# 타겟 버전 (이전에 실패했던 문제를 해결하기 위한 고정 버전)
V="580.159.04-1ubuntu1"

echo "=============================================="
echo " Pre-flight Version Verification (Dry-run)"
echo " Target Version: $V"
echo "=============================================="

PACKAGES=(
    "nvidia-driver-580-open"
    "nvidia-dkms-580-open"
    "nvidia-fabricmanager-580"
    "nvidia-imex"
    "libnvidia-nscq-580"
)

FAILED=0

echo "[Step 1] Checking package availability in Repository..."
for PKG in "${PACKAGES[@]}"; do
    printf "  Checking %-25s : " "$PKG"
    if apt-cache madison "$PKG" | grep -q "$V"; then
        echo -e "\e[32m[MATCH]\e[0m"
    else
        echo -e "\e[31m[NOT FOUND]\e[0m"
        # 실제 리포지토리에 있는 최신 버전들을 참고용으로 출력
        AVAILABLE=$(apt-cache madison "$PKG" | head -n 1 | awk '{print $3}')
        echo "    → Available latest: $AVAILABLE"
        FAILED=1
    fi
done

echo ""
echo "[Step 2] Simulating Installation (Dependency Check)..."
if [ $FAILED -eq 0 ]; then
    # 시뮬레이션 모드(-s)로 실제 설치 시 의존성 충돌 여부 확인
    if sudo apt-get install -s \
        nvidia-driver-580-open=$V \
        nvidia-dkms-580-open=$V \
        nvidia-fabricmanager-580=$V \
        nvidia-imex=$V \
        libnvidia-nscq-580=$V > /dev/null 2>&1; then
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
