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
SIMPLEWALLET_BIN="${BIN_DIR}/simplewallet"
WALLET_FILE="${WALLET_DIR}/miner.wallet"
WALLET_PASSWORD_FILE="${WALLET_DIR}/miner-password.txt"
CONFIG_FILE="${CONFIG_DIR}/Discrete.conf"
PID_FILE="${PID_DIR}/discreted.pid"
LOG_FILE="${LOG_DIR}/discreted.log"

P2P_PORT="${P2P_PORT:-9330}"
RPC_PORT="${RPC_PORT:-9331}"
P2P_BIND_IP="${P2P_BIND_IP:-0.0.0.0}"
RPC_BIND_IP="${RPC_BIND_IP:-127.0.0.1}"
LOG_LEVEL="${LOG_LEVEL:-2}"

banner() {
    cat <<'EOF'
  ____  _           _      _
 |  _ \(_)___  ___| |_ ___| |_ ___
 | | | | / __|/ __| __/ _ \ __/ _ \
 | |_| | \__ \ (__| ||  __/ ||  __/
 |____/|_|___/\___|\__\___|\__\___|

   Console / Interactive Toolkit
EOF
    echo ""
}

check_prerequisites() {
    if [[ ! -f "${DAEMON_BIN}" ]]; then
        echo "[ERROR] discreted not found in ${BIN_DIR}" >&2
        echo "Run: bash scripts/01-setup.sh" >&2
        exit 1
    fi
    mkdir -p "${DATA_DIR}" "${LOG_DIR}" "${PID_DIR}" "${CONFIG_DIR}" "${WALLET_DIR}"
}

ensure_config() {
    if [[ ! -f "${CONFIG_FILE}" ]]; then
        cat > "${CONFIG_FILE}" <<EOF
# Discrete daemon configuration (REFERENCE ONLY).
# All scripts pass settings via explicit CLI flags.
p2p-bind-ip ${P2P_BIND_IP}
p2p-bind-port ${P2P_PORT}
rpc-bind-ip ${RPC_BIND_IP}
rpc-bind-port ${RPC_PORT}
log-level ${LOG_LEVEL}
data-dir ${DATA_DIR}
EOF
    fi
}

menu() {
    local choice
    while true; do
        echo "========================================"
        echo " Main Menu"
        echo "========================================"
        echo ""
        echo "  1)  Start daemon with INTERACTIVE CONSOLE"
        echo "  2)  Start daemon + mining (interactive console)"
        echo "  3)  Open simplewallet console"
        echo "  4)  Mining commands via daemon console (running daemon)"
        echo "  5)  View live logs (tail -f)"
        echo "  6)  Check status summary"
        echo "  7)  Stop daemon"
        echo "  8)  Verify binaries exist + version"
        echo ""
        echo "  0)  Exit"
        echo ""
        read -r -p "Choice [0-8]: " choice
        echo ""
        case "${choice}" in
            1) cmd_daemon_console ;;
            2) cmd_daemon_mining_console ;;
            3) cmd_simplewallet ;;
            4) cmd_mining_control ;;
            5) cmd_view_logs ;;
            6) bash "${SCRIPT_DIR}/06-check-status.sh" ;;
            7) bash "${SCRIPT_DIR}/05-stop.sh" ;;
            8) cmd_version ;;
            0) echo "Bye."; exit 0 ;;
            *) echo "[?] Invalid choice" ;;
        esac
        echo ""
        read -r -s -p "Press Enter to continue..." _
        echo ""
    done
}

cmd_daemon_console() {
    echo "[INFO] Launching discreted interactive console (no mining)..."
    echo "[INFO] Useful daemon commands: status, print_cn, print_pl, height, print_diff, exit"
    echo ""
    read -r -s -p "Press Enter to launch..." _
    echo ""
    exec "${DAEMON_BIN}" \
        --data-dir "${DATA_DIR}" \
        --log-file "${LOG_FILE}" \
        --p2p-bind-ip "${P2P_BIND_IP}" \
        --p2p-bind-port "${P2P_PORT}" \
        --rpc-bind-ip "${RPC_BIND_IP}" \
        --rpc-bind-port "${RPC_PORT}" \
        --log-level "${LOG_LEVEL}"
}

cmd_daemon_mining_console() {
    if [[ ! -f "${WALLET_FILE}" ]]; then
        echo "[ERROR] Wallet not found: ${WALLET_FILE}"
        echo "Run 02-create-wallet.sh first or provide a wallet via -w"
        return 1
    fi

    local threads
    read -r -p "Mining thread count [1]: " threads
    threads="${threads:-1}"

    echo ""
    echo "[INFO] Launching discreted with interactive console + mining ${threads} thread(s)..."
    echo "[INFO] Mining wallet: ${WALLET_FILE}"
    echo "[INFO] When the daemon prompt appears, run:"
    echo "        start_mining ${WALLET_FILE} ${threads}"
    echo "      or if using password file:"
    echo "        start_mining ${WALLET_FILE} ${threads} --mining-password-file ${WALLET_PASSWORD_FILE}"
    echo "[INFO] Other commands: show_hr, hide_hr, print_diff, status, stop_mining, exit"
    echo ""
    read -r -s -p "Press Enter to launch..." _
    echo ""
    exec "${DAEMON_BIN}" \
        --data-dir "${DATA_DIR}" \
        --log-file "${LOG_FILE}" \
        --p2p-bind-ip "${P2P_BIND_IP}" \
        --p2p-bind-port "${P2P_PORT}" \
        --rpc-bind-ip "${RPC_BIND_IP}" \
        --rpc-bind-port "${RPC_PORT}" \
        --log-level "${LOG_LEVEL}"
}

cmd_simplewallet() {
    if [[ ! -f "${SIMPLEWALLET_BIN}" ]]; then
        echo "[ERROR] simplewallet not found: ${SIMPLEWALLET_BIN}"
        return 1
    fi
    if [[ ! -f "${WALLET_FILE}" ]]; then
        echo "[ERROR] Wallet not found: ${WALLET_FILE}"
        echo "Run 02-create-wallet.sh first."
        return 1
    fi
    if [[ ! -f "${WALLET_PASSWORD_FILE}" ]]; then
        echo "[ERROR] Password file not found: ${WALLET_PASSWORD_FILE}"
        return 1
    fi
    local wallet_password
    wallet_password="$(< "${WALLET_PASSWORD_FILE}")"
    echo "[INFO] Launching simplewallet console against local 127.0.0.1:${RPC_PORT}..."
    echo "[INFO] Useful wallet commands: balance, address, print_seed, start_mining N, stop_mining, help, exit"
    echo "[INFO] (simplewallet uses inline --password; read from ${WALLET_PASSWORD_FILE})"
    echo ""
    read -r -s -p "Press Enter to launch..." _
    echo ""
    exec "${SIMPLEWALLET_BIN}" \
        --wallet-file "${WALLET_FILE}" \
        --password "${wallet_password}" \
        --daemon-address "127.0.0.1:${RPC_PORT}"
}

cmd_mining_control() {
    echo "Mining control (for a RUNNING headless daemon):"
    echo ""
    echo "Useful RPC via curl examples:"
    cat <<EOF

  # Check if mining running:
  curl -s http://127.0.0.1:9331/json_rpc -X POST -H 'Content-Type: application/json' \\
    -d '{"jsonrpc":"2.0","id":"0","method":"get_info"}' | python3 -m json.tool

  # Start mining (if wallet loaded in daemon):
  curl -s http://127.0.0.1:9331/json_rpc -X POST -H 'Content-Type: application/json' \\
    -d '{"jsonrpc":"2.0","id":"0","method":"start_mining","params":{"wallet_file":"'${WALLET_FILE}'","threads_count":4}}'

  # Stop mining:
  curl -s http://127.0.0.1:9331/json_rpc -X POST -H 'Content-Type: application/json' \\
    -d '{"jsonrpc":"2.0","id":"0","method":"stop_mining"}'
EOF
    echo ""
    echo "Or connect to daemon console interactively by running:"
    echo "  ${DAEMON_BIN} --config-file ${CONFIG_FILE}"
    echo "(second instance may require --rpc-bind-port to avoid conflict)"
}

cmd_view_logs() {
    if [[ ! -f "${LOG_FILE}" ]]; then
        echo "[WARN] No log file at ${LOG_FILE}. Starting daemon with logging first."
        return 1
    fi
    echo "[INFO] Viewing ${LOG_FILE}. Press Ctrl+C to exit."
    echo ""
    exec tail -n 100 -f "${LOG_FILE}"
}

cmd_version() {
    echo "Binaries in ${BIN_DIR}:"
    ls -la "${BIN_DIR}/" 2>/dev/null || echo "(empty)"
    echo ""
    if [[ -f "${DAEMON_BIN}" ]]; then
        echo "discreted --version:"
        "${DAEMON_BIN}" --version 2>&1 | head -5 || true
        echo ""
    fi
}

main() {
    banner
    check_prerequisites
    ensure_config
    menu
}

main "$@"
