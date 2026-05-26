#!/bin/bash
###############################################################################
# setup_pyenv_cuda12.8.sh
# Pyenv 개발 환경 구축 + CUDA 12.8 연동 + 빌드 의존성 자동 구성 스크립트
#
# 이 스크립트는 호스트 환경에서 컨테이너 대신 Pyenv를 이용하여 Deep Learning
# 개발 환경을 구축할 때 필요한 모든 사전 준비 및 쉘 설정을 자동화합니다.
###############################################################################
set -euo pipefail

echo "=============================================="
echo " Pyenv + CUDA 12.8 Developer Environment Setup"
echo "=============================================="

# 1. 쉘 환경 파일 감지
SHELL_CONFIG=""
if [ -n "${SHELL:-}" ]; then
    case "${SHELL}" in
        */zsh) SHELL_CONFIG="${HOME}/.zshrc" ;;
        */bash) SHELL_CONFIG="${HOME}/.bashrc" ;;
        *) SHELL_CONFIG="${HOME}/.bashrc" ;;
    esac
else
    SHELL_CONFIG="${HOME}/.bashrc"
fi
echo "[Step 1] Shell config file detected: ${SHELL_CONFIG}"

# 2. Pyenv Python 빌드 필수 의존성 및 개발 라이브러리 설치
# Pyenv로 Python 컴파일시 필수적인 라이브러리들입니다 (Ubuntu 24.04 Noble 지원)
echo "[Step 2] Installing Pyenv Python-build prerequisites..."
sudo apt-get update
sudo apt-get install -y \
    make \
    build-essential \
    libssl-dev \
    zlib1g-dev \
    libbz2-dev \
    libreadline-dev \
    libsqlite3-dev \
    wget \
    curl \
    llvm \
    libncursesw5-dev \
    xz-utils \
    tk-dev \
    libxml2-dev \
    libxmlsec1-dev \
    libffi-dev \
    liblzma-dev \
    git

# 3. Pyenv 설치 (기설치 여부 확인)
echo "[Step 3] Checking Pyenv installation..."
if [ ! -d "${HOME}/.pyenv" ] && ! command -v pyenv &>/dev/null; then
    echo "  → Installing Pyenv via pyenv-installer..."
    curl -fsSL https://pyenv.run | bash
else
    echo "  → Pyenv is already installed at ${HOME}/.pyenv"
fi

# 4. 쉘 환경 설정 (Pyenv 및 CUDA 12.8 연동 패스 주입)
echo "[Step 4] Injecting Environment Variables into ${SHELL_CONFIG}..."

# CUDA 12.8 연동 설정 정의
CUDA_ENV_BLOCK=$(cat << 'EOF'

# >>> CUDA 12.8 Environment Config >>>
if [ -d "/usr/local/cuda-12.8" ]; then
    export CUDA_HOME="/usr/local/cuda-12.8"
    export PATH="${CUDA_HOME}/bin:${PATH}"
    export LD_LIBRARY_PATH="${CUDA_HOME}/lib64:${LD_LIBRARY_PATH:-}"
fi
# <<< CUDA 12.8 Environment Config <<<
EOF
)

# Pyenv 쉘 초기화 설정 정의
PYENV_ENV_BLOCK=$(cat << 'EOF'

# >>> Pyenv Init Config >>>
export PYENV_ROOT="$HOME/.pyenv"
[[ -d $PYENV_ROOT/bin ]] && export PATH="$PYENV_ROOT/bin:$PATH"
eval "$(pyenv init -)"
eval "$(pyenv virtualenv-init -)"
# <<< Pyenv Init Config <<<
EOF
)

# 파일에 없으면 추가
if ! grep -q "CUDA 12.8 Environment Config" "${SHELL_CONFIG}" 2>/dev/null; then
    echo "  → Adding CUDA 12.8 environment configuration..."
    echo "${CUDA_ENV_BLOCK}" >> "${SHELL_CONFIG}"
fi

if ! grep -q "Pyenv Init Config" "${SHELL_CONFIG}" 2>/dev/null; then
    echo "  → Adding Pyenv initialization blocks..."
    echo "${PYENV_ENV_BLOCK}" >> "${SHELL_CONFIG}"
fi

# 5. 현재 쉘 세션 반영을 위한 안내 및 검증 가이드
echo "=============================================="
echo " Environment Configuration Complete!"
echo "=============================================="
echo ""
echo " To apply changes immediately to your current terminal session:"
echo "   source ${SHELL_CONFIG}"
echo ""
echo " How to build and verify Python + CUDA 12.8 using Pyenv:"
echo "   1) Install your preferred Python version (e.g., 3.10 or 3.11):"
echo "      pyenv install 3.10.14"
echo ""
echo "   2) Set local or global Python version:"
echo "      pyenv global 3.10.14"
echo ""
echo "   3) Create and activate a Virtualenv (Optional but recommended):"
echo "      pyenv virtualenv 3.10.14 myenv"
echo "      pyenv activate myenv"
echo ""
echo "   4) Install PyTorch (configured for CUDA 12.8 compat):"
echo "      pip install --upgrade pip"
echo "      pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu124"
echo "      (Note: PyTorch release wheels for 12.8 may use cu124/cu126 as stable back-compat,"
echo "       or download the direct CUDA 12.8 compatible wheel)"
echo ""
echo "   5) Run the validation script:"
echo "      python -c 'import torch; print(\"CUDA Available:\", torch.cuda.is_available()); print(\"Device Name:\", torch.cuda.get_device_name(0) if torch.cuda.is_available() else \"None\")'"
echo ""
echo "=============================================="
