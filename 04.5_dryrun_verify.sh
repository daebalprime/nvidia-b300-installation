#!/bin/bash
###############################################################################
# 04.5_dryrun_verify.sh
# [사전 검증] Origin Pinning 적용 후 버전 일치 여부 확인
#
# 이 스크립트는:
#   1. NVIDIA CUDA repo를 최우선 출처로 고정하는 APT Pin을 적용
#   2. 적용 후 각 패키지의 candidate 버전을 조회
#   3. 모든 패키지가 동일한 580.x.yy 버전인지 검증
#   4. dry-run으로 의존성 충돌 여부 시뮬레이션
###############################################################################
set -u

echo "=============================================="
echo " Pre-flight Version Verification (Dry-run)"
echo "=============================================="

###############################################################################
# Step 0: Origin Pinning 적용 (04_install_gpu_stack.sh와 동일)
###############################################################################
echo "[Step 0] Applying NVIDIA origin pin..."

cat <<'EOF' | sudo tee /etc/apt/preferences.d/nvidia-origin-lock > /dev/null
Package: *nvidia* *cuda* *libnvidia* *fabricmanager* *imex* *nscq* *nvlsm* *nvsdm*
Pin: origin "developer.download.nvidia.com"
Pin-Priority: 1001

Package: *nvidia* *libnvidia* *fabricmanager* *imex* *nscq*
Pin: release o=Ubuntu,n=noble-updates
Pin-Priority: 100

Package: *nvidia*
Pin: version 595.*
Pin-Priority: -1

Package: *nvidia*
Pin: version 535.*
Pin-Priority: -1
EOF

sudo apt-get update -qq

###############################################################################
# Step 1: Pinning 적용 후 candidate 버전 조회
###############################################################################
echo ""
echo "[Step 1] Checking candidate versions after origin pinning..."
echo ""

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
declare -A PKG_VERSIONS

for PKG in "${PACKAGES[@]}"; do
    # apt-cache policy는 Pin을 반영한 candidate를 보여줌
    CANDIDATE=$(apt-cache policy "$PKG" 2>/dev/null | grep "Candidate:" | awk '{print $2}')
    SOURCE=$(apt-cache policy "$PKG" 2>/dev/null | grep -A1 "\\*\\*\\*\\|${CANDIDATE}" | grep "http" | awk '{print $2}' | head -1)
    
    if [ -z "$CANDIDATE" ] || [ "$CANDIDATE" = "(none)" ]; then
        printf "  %-30s : \e[31m[NOT AVAILABLE]\e[0m\n" "$PKG"
        FAILED=1
    else
        PKG_VERSIONS[$PKG]="$CANDIDATE"
        # 580인지 확인
        if echo "$CANDIDATE" | grep -q "^580\."; then
            printf "  %-30s : \e[32m%-30s\e[0m  ← %s\n" "$PKG" "$CANDIDATE" "$SOURCE"
        else
            printf "  %-30s : \e[31m%-30s (NOT 580!)\e[0m\n" "$PKG" "$CANDIDATE"
            FAILED=1
        fi
    fi
done

###############################################################################
# Step 2: 버전 일치 여부 확인
###############################################################################
echo ""
echo "[Step 2] Checking version consistency..."

if [ $FAILED -eq 1 ]; then
    echo -e "  \e[33m[SKIP] Some packages missing or wrong branch.\e[0m"
else
    UNIQUE_VERSIONS=$(for V in "${PKG_VERSIONS[@]}"; do echo "$V" | grep -oP '580\.\d+\.\d+'; done | sort -u)
    NUM_UNIQUE=$(echo "$UNIQUE_VERSIONS" | wc -l)
    
    if [ "$NUM_UNIQUE" -eq 1 ]; then
        echo -e "  \e[32m[PASS] All packages unified at: $UNIQUE_VERSIONS\e[0m"
    else
        echo -e "  \e[31m[FAIL] Version mismatch!\e[0m"
        for PKG in "${!PKG_VERSIONS[@]}"; do
            printf "    %-30s → %s\n" "$PKG" "${PKG_VERSIONS[$PKG]}"
        done
        FAILED=1
    fi
fi

###############################################################################
# Step 3: Dry-run 시뮬레이션
###############################################################################
echo ""
echo "[Step 3] Simulating installation (apt-get install -s)..."

if [ $FAILED -eq 0 ]; then
    INSTALL_ARGS=""
    for PKG in "${!PKG_VERSIONS[@]}"; do
        INSTALL_ARGS+=" ${PKG}=${PKG_VERSIONS[$PKG]}"
    done
    
    if sudo apt-get install -s $INSTALL_ARGS > /dev/null 2>&1; then
        echo -e "  \e[32m[PASS] No dependency conflicts.\e[0m"
    else
        echo -e "  \e[31m[FAIL] Dependency conflict!\e[0m"
        sudo apt-get install -s $INSTALL_ARGS 2>&1 | grep -E "^E:|Depends:|Conflicts:" | head -10
        FAILED=1
    fi
else
    echo -e "  \e[33m[SKIP]\e[0m"
fi

###############################################################################
# 결론
###############################################################################
echo ""
echo "=============================================="
if [ $FAILED -eq 0 ]; then
    echo -e "\e[32m ✓ SAFE TO PROCEED with 04_install_gpu_stack.sh\e[0m"
else
    echo -e "\e[31m ✗ DO NOT PROCEED - Fix issues above first\e[0m"
    echo ""
    echo " Hint: run 'apt-cache policy <package>' to check which repo provides what"
fi
echo "=============================================="

exit $FAILED
