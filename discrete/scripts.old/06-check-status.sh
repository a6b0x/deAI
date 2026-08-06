#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

BIN_DIR="${PROJECT_DIR}/bin"
WALLET_DIR="${PROJECT_DIR}/wallet"
PID_DIR="${PROJECT_DIR}/run"
LOG_DIR="${PROJECT_DIR}/logs"
DATA_DIR="${PROJECT_DIR}/data"

DAEMON_BIN="${BIN_DIR}/discreted"
SIMPLEWALLET_BIN="${BIN_DIR}/simplewallet"
WALLET_FILE="${WALLET_DIR}/miner.wallet"
WALLET_PASSWORD_FILE="${WALLET_DIR}/miner-password.txt"
PID_FILE="${PID_DIR}/discreted.pid"
LOG_FILE="${LOG_DIR}/discreted.log"

RPC_HOST="${RPC_HOST:-127.0.0.1}"
RPC_PORT="${RPC_PORT:-9331}"

COLOR_BLUE='\033[1;34m'
COLOR_GREEN='\033[1;32m'
COLOR_YELLOW='\033[1;33m'
COLOR_RED='\033[1;31m'
COLOR_RESET='\033[0m'

section() {
    echo -e "${COLOR_BLUE}== $@ ==${COLOR_RESET}"
}

ok() {
    echo -e "${COLOR_GREEN}[OK]${COLOR_RESET} $@"
}

warn() {
    echo -e "${COLOR_YELLOW}[WARN]${COLOR_RESET} $@"
}

err() {
    echo -e "${COLOR_RED}[ERROR]${COLOR_RESET} $@"
}

rpc_call() {
    local method="$1"
    local params="${2:-{}}"
    local url="http://${RPC_HOST}:${RPC_PORT}/json_rpc"

    if command -v curl >/dev/null 2>&1; then
        curl -s -X POST "${url}" \
            -H "Content-Type: application/json" \
            -d "{\"jsonrpc\":\"2.0\",\"id\":\"0\",\"method\":\"${method}\",\"params\":${params}}" \
            --max-time 5 2>/dev/null || true
    else
        echo ""
    fi
}

get_status_via_rpc() {
    local resp
    resp="$(rpc_call "get_info")"
    if [[ -n "${resp}" ]]; then
        python3 - <<EOF 2>/dev/null || true
import json, sys
resp = json.loads('''${resp}''')
r = resp.get('result', {})
if r:
    print(f"Height:         {r.get('height', 'N/A')}")
    print(f"Target height:  {r.get('target_height', 'N/A')}")
    print(f"Synced:         {r.get('synced', 'N/A')}")
    print(f"Peers in:       {r.get('incoming_connections_count', 'N/A')}")
    print(f"Peers out:      {r.get('outgoing_connections_count', 'N/A')}")
    print(f"Difficulty:     {r.get('difficulty', 'N/A')}")
    print(f"Network HR:     {r.get('network_hashrate', 'N/A')} H/s")
    print(f"Mining active:  {r.get('mining_active', 'N/A')}")
    print(f"Mining threads: {r.get('mining_thread_count', 'N/A')}")
    print(f"Block size:     {r.get('block_size_limit', 'N/A')}")
    print(f"Mempool txs:    {r.get('tx_pool_size', 'N/A')}")
    print(f"Start time:     {r.get('start_time', 'N/A')}")
EOF
    fi
}

check_process() {
    section "Process Status"
    if [[ -f "${PID_FILE}" ]]; then
        local pid
        pid="$(cat "${PID_FILE}" 2>/dev/null || echo "")"
        if [[ -n "${pid}" ]] && kill -0 "${pid}" 2>/dev/null; then
            ok "discreted running (PID ${pid})"
            echo ""
            ps -o pid,etime,%cpu,%mem,cmd -p "${pid}" --no-headers 2>/dev/null || \
                ps -p "${pid}" 2>/dev/null || true
        else
            warn "PID file exists but process dead"
            return 1
        fi
    else
        local pids
        pids="$(pgrep -f "discreted" 2>/dev/null || true)"
        if [[ -n "${pids}" ]]; then
            warn "discreted found via pgrep (no PID file): ${pids}"
        else
            err "discreted is NOT running"
            return 1
        fi
    fi
    return 0
}

check_rpc() {
    section "RPC Status (${RPC_HOST}:${RPC_PORT})"
    local resp
    resp="$(rpc_call "get_info" "{}")"
    if [[ -z "${resp}" ]]; then
        warn "RPC not reachable"
        return 1
    fi
    ok "RPC responding"
    echo ""
    get_status_via_rpc
    return 0
}

check_logs() {
    section "Recent Logs (last 20 lines)"
    if [[ -f "${LOG_FILE}" ]]; then
        tail -20 "${LOG_FILE}" 2>/dev/null || echo "(empty)"
    else
        warn "No log file found at ${LOG_FILE}"
    fi
}

check_wallet() {
    section "Mining Wallet"
    local count=0
    [[ -f "${WALLET_FILE}" ]] && { ok "Wallet file: ${WALLET_FILE}"; count=$((count+1)); } || warn "Wallet missing: ${WALLET_FILE}"
    [[ -f "${WALLET_PASSWORD_FILE}" ]] && { ok "Password file: ${WALLET_PASSWORD_FILE}"; count=$((count+1)); } || warn "Password file missing"
    local seed_file="${WALLET_DIR}/miner-seed.txt"
    [[ -f "${seed_file}" ]] && { ok "Seed backup: ${seed_file}"; count=$((count+1)); } || warn "Seed backup: not present (check manually)"
    echo ""
    echo "Wallet files present: ${count}/3"
}

check_disk() {
    section "Disk Usage"
    echo "Data dir (${DATA_DIR}):"
    if [[ -d "${DATA_DIR}" ]]; then
        du -sh "${DATA_DIR}" 2>/dev/null || true
    else
        warn "Data dir not present"
    fi
    echo ""
    echo "Project root (${PROJECT_DIR}):"
    df -h "${PROJECT_DIR}" 2>/dev/null | tail -1 || true
}

check_ports() {
    section "Listening Ports"
    if command -v ss >/dev/null 2>&1; then
        ss -tlnp | grep -E ":(9330|9331|9332)" || echo "(none listening)"
    elif command -v netstat >/dev/null 2>&1; then
        netstat -tlnp 2>/dev/null | grep -E ":(9330|9331|9332)" || echo "(none listening)"
    else
        warn "ss/netstat not available"
    fi
}

show_help() {
    cat <<EOF
Usage: $0 [check...]

Default: run ALL checks.

Specific checks:
  process   Check if discreted is running
  rpc       Query RPC /get_info
  logs      Show recent log tail
  wallet    Verify mining wallet files exist
  disk      Check data dir and disk usage
  ports     Show listening ports (9330/9331/9332)
  all       Run all (default)

Examples:
  $0 process
  $0 rpc logs
EOF
}

main() {
    if [[ "${1:-}" == "-h" ]] || [[ "${1:-}" == "--help" ]]; then
        show_help
        exit 0
    fi

    local checks=("$@")
    if [[ ${#checks[@]} -eq 0 ]]; then
        checks=("process" "rpc" "logs" "wallet" "disk" "ports")
    fi

    echo "========================================"
    echo "Discrete - Status & Diagnostics"
    echo "========================================"
    echo ""

    local c
    for c in "${checks[@]}"; do
        case "${c}" in
            all)
                check_process; echo ""
                check_rpc; echo ""
                check_logs; echo ""
                check_wallet; echo ""
                check_disk; echo ""
                check_ports
                ;;
            process) check_process; echo "" ;;
            rpc)     check_rpc; echo "" ;;
            logs)    check_logs; echo "" ;;
            wallet)  check_wallet; echo "" ;;
            disk)    check_disk; echo "" ;;
            ports)   check_ports ;;
            *)
                warn "Unknown check: ${c}"
                ;;
        esac
    done
}

main "$@"
