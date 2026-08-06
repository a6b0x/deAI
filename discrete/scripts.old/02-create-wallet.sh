#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

BIN_DIR="${PROJECT_DIR}/bin"
WALLET_DIR="${PROJECT_DIR}/wallet"
DATA_DIR="${PROJECT_DIR}/data"

WALLET_FILE="${WALLET_DIR}/miner.wallet"
WALLET_PASSWORD_FILE="${WALLET_DIR}/miner-password.txt"
WALLET_SEED_FILE="${WALLET_DIR}/miner-seed.txt"

usage() {
    cat <<EOF
Usage: $0 [options]

Create a new Discrete mining wallet.

Options:
  -p, --password PASSWORD   Set wallet password (interactive if omitted)
  -w, --wallet-file FILE    Wallet output file (default: ${WALLET_FILE})
  -f, --force               Overwrite existing wallet files
  -h, --help                Show this help

Environment variables:
  DISCRETE_PASSWORD         Can be set instead of -p (not recommended for security)

Notes:
  simplewallet CLI uses --password (inline), not --password-file.
  Seed mnemonic is written using the native --mnemonic-file flag.
EOF
}

FORCE=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        -p|--password)
            WALLET_PASSWORD="$2"
            shift 2
            ;;
        -w|--wallet-file)
            WALLET_FILE="$2"
            WALLET_DIR="$(dirname "${WALLET_FILE}")"
            WALLET_PASSWORD_FILE="${WALLET_DIR}/$(basename "${WALLET_FILE}" .wallet)-password.txt"
            WALLET_SEED_FILE="${WALLET_DIR}/$(basename "${WALLET_FILE}" .wallet)-seed.txt"
            shift 2
            ;;
        -f|--force)
            FORCE=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "[ERROR] Unknown option: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

check_prerequisites() {
    if [[ ! -f "${BIN_DIR}/simplewallet" ]]; then
        echo "[ERROR] simplewallet not found in ${BIN_DIR}" >&2
        echo "Run setup first: bash ${SCRIPT_DIR}/01-setup.sh" >&2
        exit 1
    fi
}

check_existing_wallet() {
    if [[ -f "${WALLET_FILE}" && "${FORCE}" -eq 0 ]]; then
        echo "[ERROR] Wallet already exists: ${WALLET_FILE}" >&2
        echo "Use --force to overwrite, or choose a different wallet file with -w" >&2
        exit 1
    fi
}

get_password() {
    if [[ -n "${WALLET_PASSWORD:-}" ]]; then
        return 0
    fi
    if [[ -n "${DISCRETE_PASSWORD:-}" ]]; then
        WALLET_PASSWORD="${DISCRETE_PASSWORD}"
        return 0
    fi

    echo ""
    read -r -s -p "Enter wallet password (min 8 chars recommended): " WALLET_PASSWORD
    echo ""
    read -r -s -p "Confirm wallet password: " WALLET_PASSWORD_CONFIRM
    echo ""
    if [[ "${WALLET_PASSWORD}" != "${WALLET_PASSWORD_CONFIRM}" ]]; then
        echo "[ERROR] Passwords do not match." >&2
        exit 1
    fi
    if [[ "${#WALLET_PASSWORD}" -lt 1 ]]; then
        echo "[ERROR] Password cannot be empty." >&2
        exit 1
    fi
}

write_password_file() {
    local file="$1"
    local password="$2"
    printf '%s' "${password}" > "${file}"
    chmod 600 "${file}"
}

verify_wallet() {
    echo ""
    echo "[3/3] Verifying wallet..."

    local verified=0
    local addr_out="${WALLET_DIR}/.$(basename "${WALLET_FILE}").addr"
    rm -f "${addr_out}"

    set +e
    (
        echo "address"
        echo "exit"
    ) | "${BIN_DIR}/simplewallet" \
        --wallet-file "${WALLET_FILE}" \
        --password "${WALLET_PASSWORD}" \
        --daemon-address "127.0.0.1:9331" \
        > "${addr_out}" 2>&1
    local rc=$?
    set -e

    if [[ "${rc}" -eq 0 ]] && grep -qiE "Primary|address|0x[0-9a-f]|[Pp]ublic" "${addr_out}"; then
        verified=1
    fi

    if [[ "${verified}" -eq 1 ]]; then
        echo "[OK] Wallet verified. Address output:"
        grep -vE '^[[:space:]]*$' "${addr_out}" | tail -20 || true
    else
        echo "[WARN] Wallet verification could not confirm (daemon may be offline)."
        echo "  Tail of address output:"
        tail -15 "${addr_out}" || true
    fi
    rm -f "${addr_out}"
}

main() {
    echo "========================================"
    echo "Discrete Mining Wallet Creation"
    echo "========================================"
    echo ""

    check_prerequisites
    mkdir -p "${WALLET_DIR}" "${DATA_DIR}"
    check_existing_wallet

    echo "[INFO] Wallet file:        ${WALLET_FILE}"
    echo "[INFO] Password file:      ${WALLET_PASSWORD_FILE}"
    echo "[INFO] Seed mnemonic file: ${WALLET_SEED_FILE}"
    echo ""

    get_password

    echo ""
    echo "[1/3] Writing password file (chmod 600)..."
    write_password_file "${WALLET_PASSWORD_FILE}" "${WALLET_PASSWORD}"
    echo "[OK] Password stored."

    echo ""
    echo "[2/3] Creating new wallet with simplewallet..."
    echo "  Using native --generate-new-wallet + --mnemonic-file + --password"
    echo ""

    rm -f "${WALLET_FILE}" "${WALLET_FILE}.keys" "${WALLET_FILE}.address.txt" "${WALLET_SEED_FILE}"

    set +e
    "${BIN_DIR}/simplewallet" \
        --generate-new-wallet "${WALLET_FILE}" \
        --mnemonic-file "${WALLET_SEED_FILE}" \
        --password "${WALLET_PASSWORD}" \
        --daemon-address "127.0.0.1:9331"
    local sw_exit=$?
    set -e

    if [[ "${sw_exit}" -ne 0 ]]; then
        echo "[ERROR] simplewallet create-wallet exited with code ${sw_exit}." >&2
        exit 1
    fi
    if [[ ! -f "${WALLET_FILE}" ]]; then
        echo "[ERROR] Wallet file was not created at ${WALLET_FILE}" >&2
        exit 1
    fi
    echo "[OK] Wallet file created: ${WALLET_FILE}"

    if [[ -f "${WALLET_FILE}.keys" ]]; then
        echo "[OK] Keys file:         ${WALLET_FILE}.keys"
    fi
    if [[ -s "${WALLET_SEED_FILE}" ]]; then
        chmod 600 "${WALLET_SEED_FILE}"
        echo "[OK] Seed mnemonic:     ${WALLET_SEED_FILE} ($(wc -c < "${WALLET_SEED_FILE}") bytes)"
    else
        echo "[WARN] Seed file is empty/missing. Trying to extract via interactive print_seed..."
        local seed_out="${WALLET_SEED_FILE}.tmp"
        (
            echo "print_seed"
            echo "exit"
        ) | "${BIN_DIR}/simplewallet" \
            --wallet-file "${WALLET_FILE}" \
            --password "${WALLET_PASSWORD}" \
            --daemon-address "127.0.0.1:9331" \
            > "${seed_out}" 2>&1 || true
        if [[ -s "${seed_out}" ]]; then
            mv -f "${seed_out}" "${WALLET_SEED_FILE}"
            chmod 600 "${WALLET_SEED_FILE}"
            echo "[OK] Seed extracted via print_seed (${WALLET_SEED_FILE})"
        else
            rm -f "${seed_out}"
            echo "[WARN] Could not auto-extract seed. Do it manually:"
            echo "  echo -e 'print_seed\nexit' | ${BIN_DIR}/simplewallet --wallet-file ${WALLET_FILE} --password YOUR_PASSWORD"
        fi
    fi

    echo ""
    echo "[2.5/3] Securing wallet files (chmod 600)..."
    chmod 600 "${WALLET_FILE}" "${WALLET_PASSWORD_FILE}" 2>/dev/null || true
    [[ -f "${WALLET_FILE}.keys" ]] && chmod 600 "${WALLET_FILE}.keys" || true
    [[ -f "${WALLET_FILE}.address.txt" ]] && chmod 600 "${WALLET_FILE}.address.txt" || true
    [[ -f "${WALLET_SEED_FILE}" ]] && chmod 600 "${WALLET_SEED_FILE}" || true
    echo "[OK] Permissions set."

    verify_wallet

    echo ""
    echo "========================================"
    echo "Wallet creation complete!"
    echo "========================================"
    echo ""
    echo "[CRITICAL] Backup OFFLINE immediately:"
    echo "  Wallet file:     ${WALLET_FILE}"
    [[ -f "${WALLET_FILE}.keys" ]] && echo "  Keys file:       ${WALLET_FILE}.keys"
    echo "  Password file:   ${WALLET_PASSWORD_FILE}"
    echo "  Seed phrase:     ${WALLET_SEED_FILE}"
    echo ""
    echo "[WARNING] Loss of seed/password = PERMANENT loss of mined coins."
    echo ""
    echo "Next step:"
    echo "  Sync chain (optional first): bash scripts/04-start-node.sh"
    echo "  Start headless mining:        bash scripts/03-start-mining.sh --threads N"
}

main "$@"
