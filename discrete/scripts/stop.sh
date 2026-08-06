#!/usr/bin/env bash
# Stop: 优雅停止 discreted  (SIGTERM, 等 30s, 再 SIGKILL)
# 目的: 让 LMDB 等数据结构正常 flush, 避免损坏链数据库

set +e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${PROJECT_DIR}"

PIDFILE="run/discreted.pid"

if [[ -f "${PIDFILE}" ]]; then
  PID="$(cat ${PIDFILE})"
  if kill -0 "${PID}" 2>/dev/null; then
    echo "[停止] 发送 SIGTERM 给 PID=${PID}"
    kill -TERM "${PID}" 2>/dev/null
    for i in $(seq 1 30); do
      kill -0 "${PID}" 2>/dev/null || break
      sleep 1
      [[ $((i % 5)) -eq 0 ]] && echo "  已等 ${i}s..."
    done
    if kill -0 "${PID}" 2>/dev/null; then
      echo "[强杀] 30s 未退出, SIGKILL"
      kill -9 "${PID}" 2>/dev/null
      sleep 1
    fi
    echo "[完成] 已停止"
  else
    echo "(pid 文件存在但进程已退出)"
  fi
  rm -f "${PIDFILE}"
else
  pkill -TERM -f "bin/discreted" 2>/dev/null
  sleep 2
  pgrep -a discreted && echo "还有残留, 手动 kill" || echo "[完成] 无 discreted 进程"
fi
