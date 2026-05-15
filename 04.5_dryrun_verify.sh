#!/bin/bash
###############################################################################
# 04.5_dryrun_verify.sh
# [사전 검증] 리포지토리 진단 + 버전 일치 검증
#
# 핵심: 어떤 출처(origin)에 어떤 버전이 있는지 전부 보여주고,
#       nvlink5-580 메타패키지 사용 가능 여부도 확인
###############################################################################
set -u

echo "=============================================="
echo " NVIDIA 580 Stack - Repository Diagnostic"
echo "=============================================="

###############################################################################
# Step 1: 핵심 패키지별 사용 가능한 모든 버전 + 출처 표시
###############################################################################
echo ""
echo "[Step 1] Available versions per package (all sources)"
echo "================================================================"

CORE_PACKAGES=(
    "nvidia-driver-580-open"
    "nvidia-driver-580"
    "nvidia-dkms-580-open"
    "nvidia-fabricmanager-580"
    "nvidia-imex-580"
    "libnvidia-nscq-580"
    "nvlink5-580"
)

for PKG in "${CORE_PACKAGES[@]}"; do
    echo ""
    echo "  [$PKG]"
    RESULT=$(apt-cache madison "$PKG" 2>/dev/null | head -5)
    if [ -n "$RESULT" ]; then
        echo "$RESULT" | sed 's/^/    /'
    else
        echo "    (not found in any repository)"
    fi
done

###############################################################################
# Step 2: nvlink5-580 메타패키지 의존성 확인
###############################################################################
echo ""
echo "================================================================"
echo "[Step 2] nvlink5-580 meta-package dependencies"
echo "================================================================"

if apt-cache show nvlink5-580 &>/dev/null; then
    echo ""
    echo "  Version:"
    apt-cache policy nvlink5-580 2>/dev/null | grep -E "Candidate|Installed" | sed 's/^/    /'
    echo ""
    echo "  Depends:"
    apt-cache depends nvlink5-580 2>/dev/null | grep -E "Depends|Recommends" | sed 's/^/    /'
else
    echo "  nvlink5-580 NOT found in repository"
fi

###############################################################################
# Step 3: apt-cache policy로 핀 적용 후 candidate 확인
###############################################################################
echo ""
echo "================================================================"
echo "[Step 3] Current candidate versions (with active pins)"
echo "================================================================"
echo ""

CHECK_PACKAGES=(
    "nvidia-driver-580-open"
    "nvidia-dkms-580-open"
    "nvidia-fabricmanager-580"
    "nvidia-imex-580"
    "libnvidia-nscq-580"
    "libnvidia-compute-580"
    "nvidia-utils-580"
    "nvlink5-580"
)

declare -A PKG_VERSIONS
FAILED=0

for PKG in "${CHECK_PACKAGES[@]}"; do
    CANDIDATE=$(apt-cache policy "$PKG" 2>/dev/null | grep "Candidate:" | awk '{print $2}')
    
    if [ -z "$CANDIDATE" ] || [ "$CANDIDATE" = "(none)" ]; then
        printf "  %-30s : \e[33m(not available)\e[0m\n" "$PKG"
    else
        PKG_VERSIONS[$PKG]="$CANDIDATE"
        VER_SHORT=$(echo "$CANDIDATE" | grep -oP '580\.\d+\.\d+' || echo "$CANDIDATE")
        printf "  %-30s : %s\n" "$PKG" "$CANDIDATE"
    fi
done

###############################################################################
# Step 4: 버전 통일 가능성 판단
###############################################################################
echo ""
echo "================================================================"
echo "[Step 4] Version consistency analysis"
echo "================================================================"
echo ""

# 580.x.y 부분만 추출하여 그룹화
declare -A VER_GROUPS
for PKG in "${!PKG_VERSIONS[@]}"; do
    VER_SHORT=$(echo "${PKG_VERSIONS[$PKG]}" | grep -oP '580\.\d+\.\d+' || echo "unknown")
    VER_GROUPS[$VER_SHORT]+="$PKG "
done

for VER in "${!VER_GROUPS[@]}"; do
    echo "  Version $VER:"
    for PKG in ${VER_GROUPS[$VER]}; do
        echo "    - $PKG"
    done
    echo ""
done

NUM_GROUPS=${#VER_GROUPS[@]}
if [ "$NUM_GROUPS" -eq 1 ]; then
    echo -e "  \e[32m[PASS] All packages at same version!\e[0m"
elif [ "$NUM_GROUPS" -eq 0 ]; then
    echo -e "  \e[31m[FAIL] No 580 packages found.\e[0m"
    FAILED=1
else
    echo -e "  \e[31m[FAIL] $NUM_GROUPS different versions detected.\e[0m"
    FAILED=1
fi

###############################################################################
# Step 5: Dry-run 시뮬레이션
###############################################################################
echo ""
echo "================================================================"
echo "[Step 5] Dry-run simulation"
echo "================================================================"
echo ""

if [ $FAILED -eq 0 ]; then
    INSTALL_ARGS=""
    for PKG in "${!PKG_VERSIONS[@]}"; do
        INSTALL_ARGS+=" ${PKG}=${PKG_VERSIONS[$PKG]}"
    done
    
    if sudo apt-get install -s $INSTALL_ARGS > /dev/null 2>&1; then
        echo -e "  \e[32m[PASS] No dependency conflicts.\e[0m"
    else
        echo -e "  \e[31m[FAIL] Dependency conflict:\e[0m"
        sudo apt-get install -s $INSTALL_ARGS 2>&1 | grep -E "^E:|Depends:|Conflicts:|but it is not going" | head -10 | sed 's/^/    /'
        FAILED=1
    fi
else
    # mismatch가 있어도 nvlink5-580 기준으로 시뮬레이션 시도
    echo "  Trying nvlink5-580 + nvidia-driver-580-open together..."
    if sudo apt-get install -s nvlink5-580 nvidia-driver-580-open cuda-toolkit-13-0 > /dev/null 2>&1; then
        echo -e "  \e[32m[PASS] nvlink5-580 + driver-580-open resolves cleanly!\e[0m"
        echo ""
        echo "  Resolved versions:"
        sudo apt-get install -s nvlink5-580 nvidia-driver-580-open cuda-toolkit-13-0 2>/dev/null \
            | grep "^Inst" | grep -i nvidia | sed 's/^/    /'
        FAILED=0
    else
        echo -e "  \e[31m[FAIL] Cannot resolve even with meta-package.\e[0m"
        sudo apt-get install -s nvlink5-580 nvidia-driver-580-open 2>&1 | grep -E "^E:|Depends:|Conflicts:|but" | head -10 | sed 's/^/    /'
    fi
fi

###############################################################################
# 결론
###############################################################################
echo ""
echo "=============================================="
if [ $FAILED -eq 0 ]; then
    echo -e "\e[32m ✓ SAFE TO PROCEED\e[0m"
else
    echo -e "\e[31m ✗ DO NOT PROCEED - Review diagnostic above\e[0m"
fi
echo "=============================================="

exit $FAILED
