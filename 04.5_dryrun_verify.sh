#!/bin/bash
###############################################################################
# 04.5_dryrun_verify.sh
# [사전 검증] 580.159.04 통일 설치 시뮬레이션
###############################################################################
set -u

DRV_V="580.159.04-1ubuntu1"
NVL_V="580.159.04-1"

echo "=============================================="
echo " Dry-run Verification (580.159.04)"
echo " Driver: $DRV_V"
echo " NVLink: $NVL_V"
echo "=============================================="

FAILED=0

# Step 1: 패키지 존재 확인
echo ""
echo "[Step 1] Checking package availability..."

declare -A CHECKS=(
    ["nvidia-driver-580-open"]="$DRV_V"
    ["nvidia-dkms-580-open"]="$DRV_V"
    ["nvidia-utils-580"]="$DRV_V"
    ["nvlink5-580"]="$NVL_V"
)

for PKG in "${!CHECKS[@]}"; do
    VER="${CHECKS[$PKG]}"
    printf "  %-30s = %-25s : " "$PKG" "$VER"
    if apt-cache madison "$PKG" | grep -q "$VER"; then
        echo -e "\e[32m[FOUND]\e[0m"
    else
        echo -e "\e[31m[NOT FOUND]\e[0m"
        apt-cache madison "$PKG" | head -3 | sed 's/^/    /'
        FAILED=1
    fi
done

# Step 2: Dry-run 시뮬레이션
echo ""
echo "[Step 2] Simulating installation..."

if [ $FAILED -eq 0 ]; then
    SIM_OUTPUT=$(sudo apt-get install -s \
        nvidia-driver-580-open="$DRV_V" \
        nvidia-dkms-580-open="$DRV_V" \
        nvidia-utils-580="$DRV_V" \
        nvlink5-580="$NVL_V" \
        cuda-toolkit-13-0 2>&1)
    
    if [ $? -eq 0 ]; then
        echo -e "  \e[32m[PASS] No dependency conflicts.\e[0m"
        echo ""
        echo "  Key packages that would be installed:"
        echo "$SIM_OUTPUT" | grep "^Inst" | grep -iE "nvidia|cuda|fabric|imex|nscq|nvlink" | sed 's/^/    /'
    else
        echo -e "  \e[31m[FAIL] Dependency conflict:\e[0m"
        echo "$SIM_OUTPUT" | grep -E "^E:|Depends:|Conflicts:|Breaks:|but" | head -15 | sed 's/^/    /'
        FAILED=1
    fi
else
    echo -e "  \e[33m[SKIP] Fix missing packages first.\e[0m"
fi

# 결론
echo ""
echo "=============================================="
if [ $FAILED -eq 0 ]; then
    echo -e "\e[32m ✓ SAFE TO PROCEED with 04_install_gpu_stack.sh\e[0m"
else
    echo -e "\e[31m ✗ DO NOT PROCEED\e[0m"
fi
echo "=============================================="

exit $FAILED
