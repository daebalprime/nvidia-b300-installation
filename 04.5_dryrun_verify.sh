#!/bin/bash
###############################################################################
# 04.5_dryrun_verify.sh
# [사전 검증] 리포지토리에서 580 브랜치 패키지들의 버전 일치 여부를 확인
#
# 하드코딩된 버전이 아니라, 리포지토리에서 실제로 사용 가능한 580 버전을
# 자동 탐지한 뒤 모든 핵심 패키지가 그 버전으로 통일 가능한지 검증합니다.
###############################################################################
set -u

echo "=============================================="
echo " Pre-flight Version Verification (Dry-run)"
echo "=============================================="

# 580 브랜치 패키지 목록
# 핵심: "-580" 접미사가 붙은 패키지명을 사용해야 595 브랜치 오염을 방지
PACKAGES=(
    "nvidia-driver-580-open"
    "nvidia-dkms-580-open"
    "nvidia-utils-580"
    "nvidia-fabricmanager-580"
    "nvidia-imex-580"
    "libnvidia-nscq-580"
    "libnvidia-compute-580"
)

FAILED=0

###############################################################################
# Step 1: 리포지토리에서 각 패키지의 사용 가능한 580 버전 조회
###############################################################################
echo ""
echo "[Step 1] Querying available 580.x versions from repository..."
echo ""

declare -A PKG_VERSIONS

for PKG in "${PACKAGES[@]}"; do
    # madison 결과에서 580.x 버전만 추출
    AVAIL=$(apt-cache madison "$PKG" 2>/dev/null | awk '{print $3}' | grep "^580\." | head -n 1)
    
    if [ -z "$AVAIL" ]; then
        printf "  %-30s : \e[31m[NO 580.x VERSION FOUND]\e[0m\n" "$PKG"
        # 혹시 접미사 없는 버전이 있는지도 확인
        AVAIL_ANY=$(apt-cache madison "$PKG" 2>/dev/null | head -n 3)
        if [ -n "$AVAIL_ANY" ]; then
            echo "    → Available versions:"
            echo "$AVAIL_ANY" | sed 's/^/      /'
        else
            echo "    → Package not found in any repository"
        fi
        FAILED=1
    else
        PKG_VERSIONS[$PKG]="$AVAIL"
        printf "  %-30s : \e[32m%s\e[0m\n" "$PKG" "$AVAIL"
    fi
done

###############################################################################
# Step 2: 버전 일치 여부 확인
###############################################################################
echo ""
echo "[Step 2] Checking version consistency across all packages..."

if [ $FAILED -eq 1 ]; then
    echo -e "  \e[33m[SKIP] Some packages missing, cannot check consistency.\e[0m"
else
    # 모든 패키지의 버전에서 앞 3자리(580.xxx.yy)만 추출하여 비교
    UNIQUE_VERSIONS=$(for V in "${PKG_VERSIONS[@]}"; do echo "$V" | grep -oP '580\.\d+\.\d+'; done | sort -u)
    NUM_UNIQUE=$(echo "$UNIQUE_VERSIONS" | wc -l)
    
    if [ "$NUM_UNIQUE" -eq 1 ]; then
        echo -e "  \e[32m[PASS] All packages share version: $UNIQUE_VERSIONS\e[0m"
    else
        echo -e "  \e[31m[FAIL] Version mismatch detected!\e[0m"
        echo "  Found these different versions:"
        for PKG in "${!PKG_VERSIONS[@]}"; do
            printf "    %-30s → %s\n" "$PKG" "${PKG_VERSIONS[$PKG]}"
        done
        FAILED=1
    fi
fi

###############################################################################
# Step 3: Dry-run 시뮬레이션 (실제 설치 없이 의존성 충돌 검사)
###############################################################################
echo ""
echo "[Step 3] Simulating installation (apt-get install -s)..."

if [ $FAILED -eq 0 ]; then
    # 탐지된 버전으로 시뮬레이션
    INSTALL_CMD="sudo apt-get install -s"
    for PKG in "${!PKG_VERSIONS[@]}"; do
        INSTALL_CMD+=" ${PKG}=${PKG_VERSIONS[$PKG]}"
    done
    
    if eval "$INSTALL_CMD" > /dev/null 2>&1; then
        echo -e "  \e[32m[PASS] No dependency conflicts. Safe to install.\e[0m"
    else
        echo -e "  \e[31m[FAIL] Dependency conflict detected!\e[0m"
        echo "  Running again with verbose output:"
        eval "$INSTALL_CMD" 2>&1 | tail -20
        FAILED=1
    fi
else
    echo -e "  \e[33m[SKIP] Cannot simulate due to previous failures.\e[0m"
fi

###############################################################################
# 결론
###############################################################################
echo ""
echo "=============================================="
if [ $FAILED -eq 0 ]; then
    echo -e "\e[32m ✓ SAFE TO PROCEED\e[0m"
    echo ""
    echo " Detected install command:"
    for PKG in "${!PKG_VERSIONS[@]}"; do
        echo "   ${PKG}=${PKG_VERSIONS[$PKG]}"
    done
else
    echo -e "\e[31m ✗ DO NOT PROCEED - Fix issues above first\e[0m"
fi
echo "=============================================="

exit $FAILED
