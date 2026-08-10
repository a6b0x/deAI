#!/usr/bin/env bash
set -euo pipefail

# -----------------------------------------------------------------------------
# cmd_start.sh —— start 命令模块
#
# 职责：
# - 预检（二进制可执行、矿池连通、磁盘空间、GPU 温度/冲突进程）
# - 日志轮转 + 可选版本检查
# - flock 防并发
# - nohup 拉起后台 supervisor
# -----------------------------------------------------------------------------

source "$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/common.sh"

pearl_hash_cmd_start() {
  pearl_hash_ensure_dirs
  pearl_hash_load_config

  pearl_hash_cleanup_stale_pid_file "$SUPERVISOR_PID_FILE"
  pearl_hash_cleanup_stale_pid_file "$MINER_PID_FILE"

  local supervisor_pid
  supervisor_pid="$(pearl_hash_read_pid_file "$SUPERVISOR_PID_FILE" 2>/dev/null || true)"
  if [[ -n "$supervisor_pid" ]] && pearl_hash_is_pid_running "$supervisor_pid"; then
    pearl_hash_warn "检测到 supervisor 已在运行（pid=${supervisor_pid}），跳过 start"
    return 0
  fi

  # 矿工二进制校验
  local miner_bin
  miner_bin="$(pearl_hash_miner_bin)"
  if [[ ! -f "$miner_bin" ]]; then
    pearl_hash_err "未找到矿工二进制：${miner_bin}"
    pearl_hash_err "提示：先执行 ./pearl_hash update 下载，或手动将二进制放到 ${BIN_DIR}/ 下并确保可执行"
    return 1
  fi
  if [[ ! -x "$miner_bin" ]]; then
    chmod +x -- "$miner_bin" 2>/dev/null || true
  fi
  [[ -x "$miner_bin" ]] || {
    pearl_hash_err "矿工二进制不可执行：${miner_bin}"
    return 1
  }

  # 环境预检
  pearl_hash_check_pool_connectivity "$POOL_HOST" "$POOL_DNS_CHECK" "$POOL_TCP_CHECK" "$POOL_TCP_TIMEOUT_SEC" "$NETWORK_HINT"
  pearl_hash_disk_space_warn "$MIN_DISK_SPACE_MB"
  pearl_hash_gpu_check_and_warn_or_fail "$GPU_DEVICES" "$GPU_STRICT_EXCLUSIVE" "$GPU_IGNORE_PROCS" "$MAX_GPU_TEMP"
  pearl_hash_rotate_miner_log_if_needed

  # 可选版本检查
  if [[ "${AUTO_VERSION_CHECK_ON_START}" == "true" ]]; then
    pearl_hash_cmd_check_update 2>/dev/null || true
  fi

  # 防并发启动
  exec 9>"$START_LOCK_FILE"
  if ! flock -n 9; then
    pearl_hash_warn "检测到另一个 start 操作正在进行，已跳过"
    return 0
  fi

  rm -f -- "$MANUAL_STOP_FLAG"

  # 拉起后台 supervisor
  nohup "$SCRIPT_DIR/pearl_hash" __supervisor >>"$LOG_FILE" 2>&1 &
  local pid=$!
  pearl_hash_write_pid_file_atomic "$SUPERVISOR_PID_FILE" "$pid"

  sleep 1
  local miner_pid
  miner_pid="$(pearl_hash_read_pid_file "$MINER_PID_FILE" 2>/dev/null || true)"
  if [[ -n "$miner_pid" ]]; then
    pearl_hash_log "已启动：supervisor pid=${pid}, miner pid=${miner_pid}"
  else
    pearl_hash_log "已启动：supervisor pid=${pid}（矿工 PID 将稍后写入 ${MINER_PID_FILE}）"
  fi
}
