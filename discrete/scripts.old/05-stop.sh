#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

PID_DIR="${PROJECT_DIR}/run"
PID_FILE="${PID_DIR}/discreted.pid"
LOG_DIR="${PROJECT_DIR}/logs"
LOG_FILE="${LOG_DIR}/discreted.log"

STOP_TIMEOUT="${STOP_TIMEOUT:-60}"

usage() {
    cat <<EOF
Usage: $0 [options]

Stop Discrete daemon (discreted) cleanly.
Sends SIGTERM, waits, then SIGKILL if still running.

Options:
  -f, --force             Skip wait, SIGKILL immediately (not recommended)
  -t, --timeout SECONDS   Seconds to wait before SIGKILL (default: ${STOP_TIMEOUT})
  -h, --help              Show this help
EOF
}

FORCE=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        -f|--force)
            FORCE=1
            shift
            ;;
        -t|--timeout)
            STOP_TIMEOUT="$2"
            shift 2
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

find_pid() {
    if [[ -f "${PID_FILE}" ]]; then
        local p
        p="$(cat "${PID_FILE}" 2>/dev/null || echo "")"
        if [[ -n "${p}" ]] && kill -0 "${p}" 2>/dev/null; then
            echo "${p}"
            return
        fi
    fi
    local pids
    pids="$(pgrep -f "discreted" 2>/dev/null | head -1 || true)"
    echo "${pids}"
}

main() {
    echo "========================================"
    echo "Discrete - Stop Daemon"
    echo "========================================"
    echo ""

    local pid
    pid="$(find_pid)"

    if [[ -z "${pid}" ]]; then
        echo "[OK] discreted is not running."
        rm -f "${PID_FILE}"
        exit 0
    fi

    echo "[INFO] Found discreted PID: ${pid}"
    echo ""

    if [[ "${FORCE}" -eq 1 ]]; then
        echo "[1/2] Sending SIGKILL (force mode)..."
        kill -9 "${pid}" 2>/dev/null || true
    else
        echo "[1/2] Sending SIGTERM (graceful stop)..."
        kill -TERM "${pid}" 2>/dev/null || true

        echo "[2/2] Waiting up to ${STOP_TIMEOUT}s for clean shutdown..."
        local waited=0
        while [[ "${waited}" -lt "${STOP_TIMEOUT}" ]]; do
            if ! kill -0 "${pid}" 2>/dev/null; then
                break
            fi
            sleep 1
            waited=$((waited + 1))
            if (( waited % 10 == 0 )); then
                echo "  ... waited ${waited}s, process still alive"
            fi
        done

        if kill -0 "${pid}" 2>/dev/null; then
            echo "[WARN] Process did not exit within ${STOP_TIMEOUT}s. Sending SIGKILL."
            kill -9 "${pid}" 2>/dev/null || true
            sleep 2
        fi
    fi

    if kill -0 "${pid}" 2>/dev/null; then
        echo "[ERROR] Failed to stop process ${pid}."
        exit 1
    fi

    rm -f "${PID_FILE}"
    echo ""
    echo "[OK] discreted stopped cleanly."
    if [[ -f "${LOG_FILE}" ]]; then
        local last_lines
        last_lines="$(tail -3 "${LOG_FILE}" 2>/dev/null || true)"
        if [[ -n "${last_lines}" ]]; then
            echo ""
            echo "Last 3 log lines:"
            echo "${last_lines}"
        fi
    fi
}

main "$@"
