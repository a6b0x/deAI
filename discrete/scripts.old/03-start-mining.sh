#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

BIN_DIR="${PROJECT_DIR}/bin"
WALLET_DIR="${PROJECT_DIR}/wallet"
DATA_DIR="${PROJECT_DIR}/data"
LOG_DIR="${PROJECT_DIR}/logs"
CONFIG_DIR="${PROJECT_DIR}/config"
PID_DIR="${PROJECT_DIR}/run"

DAEMON_BIN="${BIN_DIR}/discreted"
CONFIG_FILE="${CONFIG_DIR}/Discrete.conf"
PID_FILE="${PID_DIR}/discreted.pid"
LOG_FILE="${LOG_DIR}/discreted.log"

WALLET_FILE="${WALLET_DIR}/miner.wallet"
WALLET_PASSWORD_FILE="${WALLET_DIR}/miner-password.txt"

MINING_THREADS="${MINING_THREADS:-0}"
P2P_PORT="${P2P_PORT:-9330}"
RPC_PORT="${RPC_PORT:-9331}"
P2P_BIND_IP="${P2P_BIND_IP:-0.0.0.0}"
RPC_BIND_IP="${RPC_BIND_IP:-127.0.0.1}"
LOG_LEVEL="${LOG_LEVEL:-2}"

usage() {
    cat <<EOF
Usage: $0 [options]

Start Discrete headless daemon WITH mining (recommended for unattended operation).
This uses discreted --mining-wallet flags directly.

Requires wallet already created (run 02-create-wallet.sh first).

Options:
  -t, --threads N           Mining threads (0 = auto 1 thread, default)
  -w, --wallet FILE         Wallet file path (default: ${WALLET_FILE})
  -p, --password-file FILE  Wallet password file (default: auto)
      --p2p-port PORT       P2P port (default: ${P2P_PORT})
      --rpc-port PORT       RPC port (default: ${RPC_PORT})
      --p2p-bind-ip IP      P2P bind IP (default: ${P2P_BIND_IP})
      --rpc-bind-ip IP      RPC bind IP (default: ${RPC_BIND_IP})
  -f, --foreground          Run in foreground (no daemonize)
  -h, --help                Show this help

Environment variables:
  MINING_THREADS, P2P_PORT, RPC_PORT, P2P_BIND_IP, RPC_BIND_IP, LOG_LEVEL
EOF
}

FOREGROUND=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        -t|--threads)
            MINING_THREADS="$2"
            shift 2
            ;;
        -w|--wallet)
            WALLET_FILE="$2"
            shift 2
            ;;
        -p|--password-file)
            WALLET_PASSWORD_FILE="$2"
            shift 2
            ;;
        --p2p-port)
            P2P_PORT="$2"
            shift 2
            ;;
        --rpc-port)
            RPC_PORT="$2"
            shift 2
            ;;
        --p2p-bind-ip)
            P2P_BIND_IP="$2"
            shift 2
            ;;
        --rpc-bind-ip)
            RPC_BIND_IP="$2"
            shift 2
            ;;
        -f|--foreground)
            FOREGROUND=1
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
    if [[ ! -f "${DAEMON_BIN}" ]]; then
        echo "[ERROR] discreted not found in ${BIN_DIR}" >&2
        echo "Run setup first: bash ${SCRIPT_DIR}/01-setup.sh" >&2
        exit 1
    fi
    if [[ ! -f "${WALLET_FILE}" ]]; then
        echo "[ERROR] Wallet not found: ${WALLET_FILE}" >&2
        echo "Create wallet first: bash ${SCRIPT_DIR}/02-create-wallet.sh" >&2
        exit 1
    fi
    if [[ ! -f "${WALLET_PASSWORD_FILE}" ]]; then
        echo "[ERROR] Wallet password file not found: ${WALLET_PASSWORD_FILE}" >&2
        exit 1
    fi
}

check_running() {
    if [[ -f "${PID_FILE}" ]]; then
        local old_pid
        old_pid="$(cat "${PID_FILE}" 2>/dev/null || echo "")"
        if [[ -n "${old_pid}" ]] && kill -0 "${old_pid}" 2>/dev/null; then
            echo "[WARN] discreted already running (PID ${old_pid}). Stop first with 05-stop.sh"
            exit 0
        else
            rm -f "${PID_FILE}"
        fi
    fi
}

ensure_dirs() {
    mkdir -p "${DATA_DIR}" "${LOG_DIR}" "${PID_DIR}" "${CONFIG_DIR}"
}

write_default_config() {
    if [[ ! -f "${CONFIG_FILE}" ]]; then
        cat > "${CONFIG_FILE}" <<EOF
# Discrete daemon configuration (REFERENCE ONLY — not passed to discreted).
# This project passes all settings via explicit CLI flags to avoid
# boost::program_options config-file parser edge cases.  See discreted --help.

p2p-bind-ip ${P2P_BIND_IP}
p2p-bind-port ${P2P_PORT}
rpc-bind-ip ${RPC_BIND_IP}
rpc-bind-port ${RPC_PORT}
log-level ${LOG_LEVEL}
data-dir ${DATA_DIR}
EOF
        echo "[INFO] Wrote reference config: ${CONFIG_FILE} (settings are applied via CLI flags, not loaded)"
    fi
}

start_foreground() {
    echo "[INFO] Starting discreted in foreground mode..."
    echo "[INFO] Mining threads: ${MINING_THREADS}"
    echo "[INFO] P2P: ${P2P_BIND_IP}:${P2P_PORT}"
    echo "[INFO] RPC: ${RPC_BIND_IP}:${RPC_PORT}"
    echo "[INFO] Log: stdout/stderr (also ${LOG_FILE})"
    echo ""
    echo "Press Ctrl+C to stop."
    echo ""

    exec "${DAEMON_BIN}" \
        --data-dir "${DATA_DIR}" \
        --log-file "${LOG_FILE}" \
        --p2p-bind-ip "${P2P_BIND_IP}" \
        --p2p-bind-port "${P2P_PORT}" \
        --rpc-bind-ip "${RPC_BIND_IP}" \
        --rpc-bind-port "${RPC_PORT}" \
        --log-level "${LOG_LEVEL}" \
        --mining-wallet "${WALLET_FILE}" \
        --mining-password-file "${WALLET_PASSWORD_FILE}" \
        --mining-threads "${MINING_THREADS}" \
        --no-console
}

start_background() {
    echo "[INFO] Starting discreted daemon (background)..."
    echo "[INFO] Mining threads: ${MINING_THREADS}"
    echo "[INFO] P2P: ${P2P_BIND_IP}:${P2P_PORT}"
    echo "[INFO] RPC: ${RPC_BIND_IP}:${RPC_PORT}"
    echo "[INFO] Log file: ${LOG_FILE}"
    echo "[INFO] PID file: ${PID_FILE}"
    echo ""

    nohup "${DAEMON_BIN}" \
        --data-dir "${DATA_DIR}" \
        --log-file "${LOG_FILE}" \
        --p2p-bind-ip "${P2P_BIND_IP}" \
        --p2p-bind-port "${P2P_PORT}" \
        --rpc-bind-ip "${RPC_BIND_IP}" \
        --rpc-bind-port "${RPC_PORT}" \
        --log-level "${LOG_LEVEL}" \
        --mining-wallet "${WALLET_FILE}" \
        --mining-password-file "${WALLET_PASSWORD_FILE}" \
        --mining-threads "${MINING_THREADS}" \
        --no-console \
        >> "${LOG_FILE}" 2>&1 &

    local pid=$!
    echo "${pid}" > "${PID_FILE}"

    sleep 2
    if kill -0 "${pid}" 2>/dev/null; then
        echo "[OK] discreted started (PID ${pid})"
        echo ""
        echo "Useful commands:"
        echo "  Check status:    bash scripts/06-check-status.sh"
        echo "  View logs:       tail -f ${LOG_FILE}"
        echo "  Stop daemon:     bash scripts/05-stop.sh"
    else
        echo "[ERROR] discreted failed to start. Check logs:"
        tail -50 "${LOG_FILE}" 2>/dev/null || true
        rm -f "${PID_FILE}"
        exit 1
    fi
}

main() {
    echo "========================================"
    echo "Discrete - Start Headless Miner"
    echo "========================================"
    echo ""

    check_prerequisites
    ensure_dirs
    write_default_config
    check_running

    if [[ "${FOREGROUND}" -eq 1 ]]; then
        start_foreground
    else
        start_background
    fi
}

main "$@"
