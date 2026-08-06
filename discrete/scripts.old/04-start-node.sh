#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

BIN_DIR="${PROJECT_DIR}/bin"
DATA_DIR="${PROJECT_DIR}/data"
LOG_DIR="${PROJECT_DIR}/logs"
CONFIG_DIR="${PROJECT_DIR}/config"
PID_DIR="${PROJECT_DIR}/run"

DAEMON_BIN="${BIN_DIR}/discreted"
CONFIG_FILE="${CONFIG_DIR}/Discrete.conf"
PID_FILE="${PID_DIR}/discreted.pid"
LOG_FILE="${LOG_DIR}/discreted.log"

P2P_PORT="${P2P_PORT:-9330}"
RPC_PORT="${RPC_PORT:-9331}"
P2P_BIND_IP="${P2P_BIND_IP:-0.0.0.0}"
RPC_BIND_IP="${RPC_BIND_IP:-127.0.0.1}"
LOG_LEVEL="${LOG_LEVEL:-2}"

usage() {
    cat <<EOF
Usage: $0 [options]

Start Discrete node ONLY (no mining). Use this to sync the chain first
before starting mining, or to run a public node.

Options:
      --p2p-port PORT       P2P port (default: ${P2P_PORT})
      --rpc-port PORT       RPC port (default: ${RPC_PORT})
      --p2p-bind-ip IP      P2P bind IP (default: ${P2P_BIND_IP})
      --rpc-bind-ip IP      RPC bind IP (default: ${RPC_BIND_IP})
  -f, --foreground          Run in foreground
      --console             Run with interactive console (no --no-console)
  -h, --help                Show this help
EOF
}

FOREGROUND=0
WITH_CONSOLE=0
while [[ $# -gt 0 ]]; do
    case "$1" in
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
        --console)
            WITH_CONSOLE=1
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
# This project applies all settings via explicit CLI flags to avoid
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

main() {
    echo "========================================"
    echo "Discrete - Start Node (No Mining)"
    echo "========================================"
    echo ""

    check_prerequisites
    ensure_dirs
    write_default_config
    check_running

    echo "[INFO] P2P: ${P2P_BIND_IP}:${P2P_PORT}"
    echo "[INFO] RPC: ${RPC_BIND_IP}:${RPC_PORT}"
    echo "[INFO] Data dir: ${DATA_DIR}"
    echo ""

    if [[ "${FOREGROUND}" -eq 1 ]]; then
        echo "[INFO] Starting in foreground..."
        [[ "${WITH_CONSOLE}" -eq 1 ]] && echo "[INFO] Interactive console enabled."
        echo ""
        local extra=()
        if [[ "${WITH_CONSOLE}" -eq 0 ]]; then
            extra+=( --no-console )
        fi
        exec "${DAEMON_BIN}" \
            --data-dir "${DATA_DIR}" \
            --log-file "${LOG_FILE}" \
            --p2p-bind-ip "${P2P_BIND_IP}" \
            --p2p-bind-port "${P2P_PORT}" \
            --rpc-bind-ip "${RPC_BIND_IP}" \
            --rpc-bind-port "${RPC_PORT}" \
            --log-level "${LOG_LEVEL}" \
            "${extra[@]}"
    else
        echo "[INFO] Starting as daemon (background)..."
        echo "[INFO] Log file: ${LOG_FILE}"
        echo "[INFO] PID file: ${PID_FILE}"
        echo ""

        local extra=()
        if [[ "${WITH_CONSOLE}" -eq 0 ]]; then
            extra+=( --no-console )
        fi

        nohup "${DAEMON_BIN}" \
            --data-dir "${DATA_DIR}" \
            --log-file "${LOG_FILE}" \
            --p2p-bind-ip "${P2P_BIND_IP}" \
            --p2p-bind-port "${P2P_PORT}" \
            --rpc-bind-ip "${RPC_BIND_IP}" \
            --rpc-bind-port "${RPC_PORT}" \
            --log-level "${LOG_LEVEL}" \
            "${extra[@]}" \
            >> "${LOG_FILE}" 2>&1 &
        local pid=$!
        echo "${pid}" > "${PID_FILE}"

        sleep 2
        if kill -0 "${pid}" 2>/dev/null; then
            echo "[OK] discreted started (PID ${pid})"
            echo ""
            echo "Useful commands:"
            echo "  Check sync status: bash scripts/06-check-status.sh"
            echo "  View live logs:    tail -f ${LOG_FILE}"
            echo "  Start mining:      bash scripts/03-start-mining.sh (stop node first)"
            echo "  Interactive mode:  bash scripts/07-interactive.sh"
        else
            echo "[ERROR] Failed to start. Tail of log:"
            tail -50 "${LOG_FILE}" 2>/dev/null || true
            rm -f "${PID_FILE}"
            exit 1
        fi
    fi
}

main "$@"
