#!/usr/bin/env bash
set -Eeuo pipefail

# ============================================================
# AIS3 Reverse Tooling Installer
#
# 安裝：
#   - GDB
#   - GDB Multiarch
#   - QEMU User-mode (qemu-i386 / qemu-aarch64)
#   - AArch64 Cross Toolchain
#   - OpenJDK 21
#   - Ghidra 12.1.2
#
# 建議環境：
#   - Ubuntu 24.04 LTS amd64
#
# 使用方式：
#   chmod +x setup.sh
#   ./setup.sh
# ============================================================

GHIDRA_VERSION="12.1.2"
GHIDRA_ARCHIVE="ghidra_12.1.2_PUBLIC_20260605.zip"
GHIDRA_DIRECTORY="ghidra_12.1.2_PUBLIC"
GHIDRA_RELEASE_TAG="Ghidra_12.1.2_build"

GHIDRA_URL="https://github.com/NationalSecurityAgency/ghidra/releases/download/${GHIDRA_RELEASE_TAG}/${GHIDRA_ARCHIVE}"

GHIDRA_SHA256="b62e81a0390618466c019c60d8c2f796ced2509c4c1aea4a37644a77272cf99d"

INSTALL_ROOT="/opt"
INSTALL_DIRECTORY="${INSTALL_ROOT}/${GHIDRA_DIRECTORY}"
CACHE_DIRECTORY="${HOME}/.cache/ais3-reverse-toolkit"
ARCHIVE_PATH="${CACHE_DIRECTORY}/${GHIDRA_ARCHIVE}"

log() {
    printf '[*] %s\n' "$*"
}

success() {
    printf '[OK] %s\n' "$*"
}

warning() {
    printf '[WARN] %s\n' "$*" >&2
}

error() {
    printf '[ERROR] %s\n' "$*" >&2
    exit 1
}

# 不建議直接使用 sudo 執行整個腳本
if [[ "${EUID}" -eq 0 ]]; then
    error "請使用一般使用者執行 ./setup.sh，不要使用 sudo ./setup.sh"
fi

# 檢查 apt
command -v apt-get >/dev/null 2>&1 ||
    error "此腳本僅支援使用 apt 的 Debian／Ubuntu 系統"

# 顯示作業系統資訊
if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    source /etc/os-release

    log "Detected OS: ${PRETTY_NAME:-unknown}"

    if [[ "${ID:-}" != "ubuntu" ||
          "${VERSION_ID:-}" != "24.04" ]]; then
        warning "正式測試環境為 Ubuntu 24.04 LTS"
        warning "目前系統仍會嘗試安裝，但不保證完全相容"
    fi

    # Ubuntu 20.04 官方庫沒有 openjdk-21，Ghidra 12.x 無法執行
    if [[ "${ID:-}" == "ubuntu" && "${VERSION_ID:-}" == "20.04" ]]; then
        error "Ubuntu 20.04 官方套件庫沒有 openjdk-21，Ghidra ${GHIDRA_VERSION} 無法執行。
       請改用 Ubuntu 24.04 LTS（建議）或 22.04 LTS。"
    fi
fi

# 安裝 Ubuntu 套件
log "Preparing apt repositories"

sudo apt-get update

# openjdk-21 在 Ubuntu 22.04 位於 universe，最小化安裝可能未啟用
if ! command -v add-apt-repository >/dev/null 2>&1; then
    sudo env DEBIAN_FRONTEND=noninteractive \
        apt-get install -y \
        --no-install-recommends \
        software-properties-common
fi

sudo add-apt-repository -y universe
sudo apt-get update

log "Installing GDB, GDB Multiarch, QEMU, cross toolchain and Java 21"

sudo env DEBIAN_FRONTEND=noninteractive \
    apt-get install -y \
    --no-install-recommends \
    ca-certificates \
    curl \
    file \
    unzip \
    openjdk-21-jdk \
    gdb \
    gdb-multiarch \
    qemu-user \
    binutils \
    gcc-aarch64-linux-gnu \
    binutils-aarch64-linux-gnu

success "System packages installed"

# 建立下載快取
mkdir -p "${CACHE_DIRECTORY}"

# 下載固定版本 Ghidra
if [[ -f "${ARCHIVE_PATH}" ]]; then
    log "Using cached Ghidra archive"
else
    log "Downloading Ghidra ${GHIDRA_VERSION} (約 400 MB，請耐心等候)"

    curl \
        --fail \
        --location \
        --retry 3 \
        --retry-delay 2 \
        --output "${ARCHIVE_PATH}.part" \
        "${GHIDRA_URL}"

    mv "${ARCHIVE_PATH}.part" "${ARCHIVE_PATH}"
fi

# 驗證 Ghidra SHA-256
log "Verifying Ghidra SHA-256"

printf '%s  %s\n' \
    "${GHIDRA_SHA256}" \
    "${ARCHIVE_PATH}" |
    sha256sum --check --status ||
    error "Ghidra SHA-256 verification failed（檔案可能下載不完整，請刪除
       ${ARCHIVE_PATH} 後重新執行）"

success "Ghidra archive verified"

# 安裝 Ghidra
if [[ -x "${INSTALL_DIRECTORY}/ghidraRun" ]]; then
    success "Ghidra ${GHIDRA_VERSION} is already installed"
else
    log "Installing Ghidra into ${INSTALL_DIRECTORY}"

    TEMP_DIRECTORY="$(mktemp -d)"

    cleanup() {
        rm -rf "${TEMP_DIRECTORY}"
    }

    trap cleanup EXIT

    unzip -q "${ARCHIVE_PATH}" -d "${TEMP_DIRECTORY}"

    if [[ ! -x "${TEMP_DIRECTORY}/${GHIDRA_DIRECTORY}/ghidraRun" ]]; then
        error "Ghidra archive structure is unexpected"
    fi

    sudo rm -rf "${INSTALL_DIRECTORY}"
    sudo mv \
        "${TEMP_DIRECTORY}/${GHIDRA_DIRECTORY}" \
        "${INSTALL_DIRECTORY}"

    sudo chown -R root:root "${INSTALL_DIRECTORY}"

    success "Ghidra installed"
fi

# 建立 ghidra 指令
sudo ln -sfn \
    "${INSTALL_DIRECTORY}/ghidraRun" \
    /usr/local/bin/ghidra

success "Created command: /usr/local/bin/ghidra"

# 環境驗證
echo
echo "========================================"
echo "Installation verification"
echo "========================================"

TOOLS=(
    gdb
    gdb-multiarch
    qemu-i386
    qemu-aarch64
    java
    ghidra
    aarch64-linux-gnu-gcc
)

FAILED=0

for tool in "${TOOLS[@]}"; do
    if command -v "${tool}" >/dev/null 2>&1; then
        printf '[OK] %-28s %s\n' \
            "${tool}" \
            "$(command -v "${tool}")"
    else
        printf '[FAIL] %s\n' "${tool}"
        FAILED=1
    fi
done

echo
echo "Versions"
echo "--------"

gdb --version | head -n 1
gdb-multiarch --version | head -n 1
qemu-i386 --version | head -n 1
qemu-aarch64 --version | head -n 1
java -version 2>&1 | head -n 1
aarch64-linux-gnu-gcc --version | head -n 1

if [[ "${FAILED}" -ne 0 ]]; then
    error "Some tools were not installed correctly"
fi

echo
success "AIS3 reverse tooling environment is ready"
echo
echo "Launch Ghidra:"
echo "  ghidra"
echo
echo "Installed tools:"
echo "  gdb"
echo "  gdb-multiarch"
echo "  qemu-i386"
echo "  qemu-aarch64"
echo "  aarch64-linux-gnu-gcc"
