#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

VERSION="v.0.9.5"
BASE_URL="https://github.com/discretecoin/discrete/releases/download/${VERSION}"

BIN_DIR="${PROJECT_DIR}/bin"
DOWNLOAD_DIR="${PROJECT_DIR}/downloads"

detect_os() {
    local os
    os="$(uname -s)"
    case "${os}" in
        Linux*) echo "linux" ;;
        Darwin*) echo "macos" ;;
        *)
            echo "Unsupported OS: ${os}" >&2
            exit 1
            ;;
    esac
}

detect_arch() {
    local arch
    arch="$(uname -m)"
    case "${arch}" in
        x86_64)  echo "x86_64" ;;
        aarch64) echo "aarch64" ;;
        arm64)   echo "aarch64" ;;
        *)
            echo "Unsupported arch: ${arch}" >&2
            exit 1
            ;;
    esac
}

detect_ubuntu_version() {
    if [[ -f /etc/os-release ]]; then
        local ubuntu_version
        ubuntu_version="$(grep '^VERSION_ID=' /etc/os-release | cut -d'"' -f2 || true)"
        echo "${ubuntu_version}"
    else
        echo ""
    fi
}

get_download_filename() {
    local os="$1"
    local arch="$2"
    local ubuntu_version="$3"

    case "${os}" in
        linux)
            if [[ "${ubuntu_version}" == "24.04" && "${arch}" == "x86_64" ]]; then
                echo "discrete-cli-ubuntu24.04-${VERSION}.tar.gz"
            else
                echo "discrete-cli-linux-universal-${VERSION}.tar.gz"
            fi
            ;;
        macos)
            if [[ "${arch}" == "aarch64" ]]; then
                echo "discrete-cli-macos-arm64-${VERSION}.zip"
            else
                echo "discrete-cli-macos-universal-${VERSION}.zip"
            fi
            ;;
        *)
            echo "Unsupported OS: ${os}" >&2
            exit 1
            ;;
    esac
}

main() {
    echo "========================================"
    echo "Discrete CLI Setup - Version ${VERSION}"
    echo "========================================"
    echo ""

    local os arch ubuntu_version filename url
    os="$(detect_os)"
    arch="$(detect_arch)"
    ubuntu_version="$(detect_ubuntu_version)"

    echo "[INFO] Detected OS: ${os}, Arch: ${arch}"
    [[ -n "${ubuntu_version}" ]] && echo "[INFO] Ubuntu version: ${ubuntu_version}"

    filename="$(get_download_filename "${os}" "${arch}" "${ubuntu_version}")"
    url="${BASE_URL}/${filename}"

    echo "[INFO] Download URL: ${url}"
    echo ""

    mkdir -p "${BIN_DIR}" "${DOWNLOAD_DIR}"

    if [[ ! -f "${DOWNLOAD_DIR}/${filename}" ]]; then
        echo "[1/4] Downloading ${filename}..."
        if command -v wget >/dev/null 2>&1; then
            wget -q --show-progress -O "${DOWNLOAD_DIR}/${filename}" "${url}"
        elif command -v curl >/dev/null 2>&1; then
            curl -L -o "${DOWNLOAD_DIR}/${filename}" "${url}"
        else
            echo "[ERROR] Neither wget nor curl found. Please install one." >&2
            exit 1
        fi
        echo "[OK] Download complete."
    else
        echo "[1/4] File already downloaded: ${filename}"
    fi

    echo ""
    echo "[2/4] Verifying SHA256 (skipped - optional manual check)..."
    echo "  Expected checksums see: https://github.com/discretecoin/discrete/releases/tag/${VERSION}"

    echo ""
    echo "[3/4] Extracting archive..."
    local extract_dir="${DOWNLOAD_DIR}/extract-tmp"
    rm -rf "${extract_dir}"
    mkdir -p "${extract_dir}"

    case "${filename}" in
        *.tar.gz)
            tar -xzf "${DOWNLOAD_DIR}/${filename}" -C "${extract_dir}"
            ;;
        *.zip)
            if command -v unzip >/dev/null 2>&1; then
                unzip -q "${DOWNLOAD_DIR}/${filename}" -d "${extract_dir}"
            else
                echo "[ERROR] unzip not found. Please install it." >&2
                exit 1
            fi
            ;;
        *)
            echo "[ERROR] Unknown archive format: ${filename}" >&2
            exit 1
            ;;
    esac
    echo "[OK] Extracted."

    echo ""
    echo "[4/4] Installing binaries to ${BIN_DIR}..."
    local found=0
    while IFS= read -r -d '' file; do
        if [[ -x "${file}" ]] || file "${file}" | grep -qi "executable\|Mach-O\|ELF"; then
            local basename
            basename="$(basename "${file}")"
            cp -f "${file}" "${BIN_DIR}/${basename}"
            chmod +x "${BIN_DIR}/${basename}"
            echo "  - ${basename}"
            found=$((found + 1))
        fi
    done < <(find "${extract_dir}" -type f -print0 2>/dev/null || true)

    if [[ "${found}" -eq 0 ]]; then
        echo "[WARN] No executables found. Listing extracted contents:"
        find "${extract_dir}" -type f 2>/dev/null || true
    fi

    rm -rf "${extract_dir}"

    echo ""
    echo "========================================"
    echo "Setup complete!"
    echo "========================================"
    echo "Binaries installed in: ${BIN_DIR}"
    echo ""
    if [[ -f "${BIN_DIR}/discreted" ]]; then
        echo "Next steps:"
        echo "  1. Run: bash scripts/02-create-wallet.sh"
        echo "  2. After wallet is ready: bash scripts/03-start-mining.sh"
    else
        echo "[WARN] discreted not found. Check extraction manually."
    fi
}

main "$@"
