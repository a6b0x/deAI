#!/usr/bin/env bash
set -euo pipefail

# -----------------------------------------------------------------------------
# supervisor.sh —— 后台守护进程模块
#
# 职责：
# - 循环拉起矿工进程
# - 启动验证（进程存活 + API/日志关键字 + 致命关键字检测）
# - 崩溃自动重启（带最大重试次数）
# - 运行时定时任务：日志轮转 + stats.jsonl 采样
# - 优雅退出：检测 .manual_stop 标志
# -----------------------------------------------------------------------------

source "$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/common.sh"

pearl_hash_startup_verify() {
  local miner_pid="$1"
  local miner_flavor="$2"

  local timeout_sec="${STARTUP_VERIFY_TIMEOUT_SEC:-30}"
  [[ "$timeout_sec" =~ ^[0-9]+$ ]] || timeout_sec=30

  local keyword=""
  if [[ "$miner_flavor" == "pearl" ]]; then
    keyword="$STARTUP_VERIFY_KEYWORD_PEARL"
  else
    keyword="$STARTUP_VERIFY_KEYWORD_WILDRIG"
  fi

  local start_ts
  start_ts="$(date +%s)"

  while true; do
    if ! pearl_hash_is_pid_running "$miner_pid"; then
      pearl_hash_err "启动验证失败：矿工进程已退出（pid=${miner_pid}）"
      return 1
    fi

    # 失败关键字检测：只对日志末尾 64KB 做 grep（性能优化，避免大文件全量扫描）
    local fails
    fails="$(pearl_hash_health_read_tail_bytes "$LOG_FILE" 65536)"
    if [[ -n "$fails" ]]; then
      local fk
      for fk in "${STARTUP_FAIL_KEYWORDS[@]:-}"; do
        [[ -n "$fk" ]] || continue
        if echo "$fails" | grep -F -- "$fk" >/dev/null 2>&1; then
          pearl_hash_err "启动验证失败：检测到失败关键字：$fk"
          return 1
        fi
      done
    fi

    # WildRig API 优先验证（比日志关键字更快）
    if [[ "$miner_flavor" == "wildrig" && "${WILDRIG_API_PORT:-0}" != "0" ]]; then
      if pearl_hash_health_wildrig_api_try_get_summary_json "$WILDRIG_API_PORT" 2 >/dev/null 2>&1; then
        return 0
      fi
    fi

    # 降级：日志关键字验证
    if [[ -n "$keyword" && -f "$LOG_FILE" ]]; then
      if pearl_hash_health_read_tail_bytes "$LOG_FILE" 65536 | grep -F -- "$keyword" >/dev/null 2>&1; then
        return 0
      fi
    fi

    local now
    now="$(date +%s)"
    if (( now - start_ts >= timeout_sec )); then
      pearl_hash_warn "启动验证超时：${timeout_sec}s 内未观察到成功标志。进程将继续运行。"
      return 0
    fi

    sleep 2
  done
}

# pearl_hash_supervisor_main: 后台守护进程主循环
# 被入口脚本通过 `nohup ./pearl_hash __supervisor` 拉起
pearl_hash_supervisor_main() {
  pearl_hash_ensure_dirs
  pearl_hash_load_config

  rm -f -- "$MANUAL_STOP_FLAG"
  pearl_hash_write_pid_file_atomic "$SUPERVISOR_PID_FILE" "$$"

  local retries=0
  local max_retries="${AUTO_RESTART_MAX_RETRIES:-5}"
  [[ "$max_retries" =~ ^[0-9]+$ ]] || max_retries=5

  while true; do
    if [[ -f "$MANUAL_STOP_FLAG" ]]; then
      break
    fi

    pearl_hash_rotate_miner_log_if_needed
    printf '\n%s\n' "==================== pearl_hash session $(pearl_hash_ts) ====================" >>"$LOG_FILE"

    local gpu_devices_csv
    gpu_devices_csv="$(pearl_hash_trim "${GPU_DEVICES:-}")"

    if [[ -n "$gpu_devices_csv" ]]; then
      pearl_hash_parse_csv_ints "$gpu_devices_csv" || {
        pearl_hash_err "GPU_DEVICES 格式错误：$gpu_devices_csv"
        break
      }
    fi

    pearl_hash_build_miner_cmd "$MINER_FLAVOR" "$POOL_HOST" "$USER_ADDRESS" "$WORKER_NAME" "$gpu_devices_csv"

    local cmd_str
    cmd_str="$(pearl_hash_cmd_to_pretty_string "${PEARL_HASH_MINER_CMD[@]}")"
    pearl_hash_log "启动矿工：${cmd_str}"

    set +e
    ( "${PEARL_HASH_MINER_CMD[@]}" >>"$LOG_FILE" 2>&1 ) &
    local miner_pid=$!
    set -e

    pearl_hash_write_pid_file_atomic "$MINER_PID_FILE" "$miner_pid"

    if ! pearl_hash_startup_verify "$miner_pid" "$MINER_FLAVOR"; then
      touch -- "$MANUAL_STOP_FLAG" || true
      pearl_hash_stop_pid_gracefully "$miner_pid" "miner" 10
      rm -f -- "$MINER_PID_FILE"
      break
    fi

    # 记录本次会话开始时间，用于定时任务的时间基准
    local session_start
    session_start="$(date +%s)"
    local last_runtime_check="${session_start}"
    local last_snapshot="${session_start}"

    local stats_interval="${LOG_STATS_INTERVAL:-60}"
    [[ "$stats_interval" =~ ^[0-9]+$ ]] || stats_interval=60
    [[ "$LOG_RUNTIME_CHECK_INTERVAL" =~ ^[0-9]+$ ]] || LOG_RUNTIME_CHECK_INTERVAL=3600

    # 轮询 wait：定时轮转 + 定时采样 + 及时感知退出
    while pearl_hash_is_pid_running "$miner_pid"; do
      local now
      now="$(date +%s)"

      # 定时日志轮转
      if (( LOG_RUNTIME_CHECK_INTERVAL > 0 )) \
         && (( now - last_runtime_check >= LOG_RUNTIME_CHECK_INTERVAL )); then
        pearl_hash_rotate_miner_log_if_needed
        last_runtime_check="$now"
      fi

      # 定时指标采样
      if [[ "${LOG_STATS_JSONL}" == "true" ]] && (( now - last_snapshot >= stats_interval )); then
        local psnapshot
        psnapshot="$(pearl_hash_health_collect_snapshot_json "$MINER_FLAVOR" "$LOG_FILE" "$STATS_FILE" "$WILDRIG_API_PORT" || true)"
        if [[ -n "$psnapshot" ]]; then
          pearl_hash_health_append_stats_jsonl "$STATS_FILE" "$psnapshot" || true
        fi
        last_snapshot="$now"
      fi

      sleep 1
    done

    rm -f -- "$MINER_PID_FILE"

    if [[ -f "$MANUAL_STOP_FLAG" ]]; then
      break
    fi

    if [[ "$AUTO_RESTART" != "true" ]]; then
      pearl_hash_warn "矿工进程退出，AUTO_RESTART=false，不再自动拉起"
      break
    fi

    retries=$((retries + 1))
    if (( retries > max_retries )); then
      pearl_hash_err "矿工连续退出次数超限（${max_retries} 次），停止自动重启"
      break
    fi

    pearl_hash_warn "矿工进程退出，将在 ${AUTO_RESTART_DELAY_SEC}s 后尝试第 ${retries}/${max_retries} 次重启"
    sleep "${AUTO_RESTART_DELAY_SEC}"
  done

  rm -f -- "$MINER_PID_FILE" "$SUPERVISOR_PID_FILE" "$MANUAL_STOP_FLAG"
}
