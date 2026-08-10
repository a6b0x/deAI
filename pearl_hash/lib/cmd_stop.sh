#!/usr/bin/env bash
set -euo pipefail

# -----------------------------------------------------------------------------
# cmd_stop.sh —— stop / pause / resume / pre_run_llm 命令模块
# -----------------------------------------------------------------------------

source "$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/common.sh"

pearl_hash_stop_pid_gracefully() {
  local pid="$1"
  local name="$2"
  local wait_sec="${3:-10}"
  [[ "$wait_sec" =~ ^[0-9]+$ ]] || wait_sec=10

  if ! pearl_hash_is_pid_running "$pid"; then
    return 0
  fi

  pearl_hash_log "发送 SIGTERM：${name} pid=${pid}"
  kill -TERM "$pid" >/dev/null 2>&1 || true

  local i
  for (( i=0; i<wait_sec; i++ )); do
    if ! pearl_hash_is_pid_running "$pid"; then
      return 0
    fi
    sleep 1
  done

  pearl_hash_warn "等待超时，发送 SIGKILL：${name} pid=${pid}"
  kill -KILL "$pid" >/dev/null 2>&1 || true
}

# stop: 优雅停止
# 流程：写 .manual_stop → 先停 miner → 再停 supervisor → 兜底残留 → 清理 PID
pearl_hash_cmd_stop() {
  local yes="${1:-false}"
  pearl_hash_ensure_dirs
  pearl_hash_cleanup_stale_pid_file "$SUPERVISOR_PID_FILE"
  pearl_hash_cleanup_stale_pid_file "$MINER_PID_FILE"

  local supervisor_pid miner_pid
  supervisor_pid="$(pearl_hash_read_pid_file "$SUPERVISOR_PID_FILE" 2>/dev/null || true)"
  miner_pid="$(pearl_hash_read_pid_file "$MINER_PID_FILE" 2>/dev/null || true)"

  if [[ -z "$supervisor_pid" && -z "$miner_pid" ]]; then
    pearl_hash_log "当前未运行"
    return 0
  fi

  # 先写标志，supervisor 见后不再自动重启
  touch -- "$MANUAL_STOP_FLAG" || true

  # 先停 miner，再停 supervisor
  if [[ -n "$miner_pid" ]]; then
    pearl_hash_stop_pid_gracefully "$miner_pid" "miner" 10
  fi

  if [[ -n "$supervisor_pid" ]]; then
    pearl_hash_stop_pid_gracefully "$supervisor_pid" "supervisor" 5
  fi

  # 兜底：清理残留（应对 watchdog/重启竞态）
  local leftover
  leftover="$(pearl_hash_read_pid_file "$MINER_PID_FILE" 2>/dev/null || true)"
  if [[ -n "$leftover" ]] && pearl_hash_is_pid_running "$leftover"; then
    pearl_hash_warn "检测到残留 miner 进程（pid=${leftover}），进行二次停止"
    pearl_hash_stop_pid_gracefully "$leftover" "miner(残留)" 5
  fi

  rm -f -- "$MINER_PID_FILE" "$SUPERVISOR_PID_FILE" "$MANUAL_STOP_FLAG"
  pearl_hash_log "已停止"
}

# pause: 冻结矿工进程（SIGSTOP），释放 CUDA 核心算力
pearl_hash_cmd_pause() {
  pearl_hash_cleanup_stale_pid_file "$MINER_PID_FILE"
  local pid
  pid="$(pearl_hash_read_pid_file "$MINER_PID_FILE" 2>/dev/null || true)"
  if [[ -z "$pid" ]]; then
    pearl_hash_err "未找到运行中的矿工 PID（${MINER_PID_FILE}）"
    return 1
  fi
  kill -STOP "$pid"
  pearl_hash_log "已暂停（SIGSTOP）：pid=${pid}"
}

# resume: 恢复矿工进程（SIGCONT）
pearl_hash_cmd_resume() {
  pearl_hash_cleanup_stale_pid_file "$MINER_PID_FILE"
  local pid
  pid="$(pearl_hash_read_pid_file "$MINER_PID_FILE" 2>/dev/null || true)"
  if [[ -z "$pid" ]]; then
    pearl_hash_err "未找到运行中的矿工 PID（${MINER_PID_FILE}）"
    return 1
  fi
  kill -CONT "$pid"
  pearl_hash_log "已恢复（SIGCONT）：pid=${pid}"
}

# pre_run_llm: 等同 pause + LLM 提示
pearl_hash_cmd_pre_run_llm() {
  if pearl_hash_cmd_pause; then
    pearl_hash_log "你现在可以启动 LLM 任务。结束后执行：./pearl_hash resume"
    return 0
  fi
  pearl_hash_err "暂停失败，请手动 stop 或排查 PID 文件"
  return 1
}
