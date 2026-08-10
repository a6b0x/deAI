#!/usr/bin/env bash
set -euo pipefail

# -----------------------------------------------------------------------------
# cmd_status.sh —— status / config / logs 命令模块
# -----------------------------------------------------------------------------

source "$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/common.sh"

pearl_hash_cmd_config() {
  pearl_hash_ensure_dirs
  pearl_hash_load_config

  local masked_addr
  masked_addr="$(pearl_hash_mask_middle "${USER_ADDRESS:-}" 10 6)"
  local lookup=""
  if [[ -n "${USER_ADDRESS:-}" ]]; then
    lookup="$(pearl_hash_lookup_url "${USER_ADDRESS}")"
  fi

  cat <<EOF
────────────────────────────────────────
pearl_hash 当前生效配置
────────────────────────────────────────
矿池地址:     ${POOL_HOST} (${POOL_REGION})
钱包地址:     ${masked_addr}
工作者名称:   ${WORKER_NAME}
查询页面:     ${lookup}
────────────────────────────────────────
矿工类型:     ${MINER_FLAVOR}
矿工文件:     $(pearl_hash_miner_bin)
WildRig API:  ${WILDRIG_API_PORT} (watchdog=${WILDRIG_WATCHDOG})
使用 GPU:     ${GPU_DEVICES:-全部}
温度上限:     ${MAX_GPU_TEMP} °C
GPU 独占:     ${GPU_STRICT_EXCLUSIVE}
────────────────────────────────────────
日志限制:     ${LOG_MAX_SIZE_MB} MB × ${LOG_ROTATE_KEEP} 份 (compress=${LOG_COMPRESS})
自动重启:     ${AUTO_RESTART} (max=${AUTO_RESTART_MAX_RETRIES}, delay=${AUTO_RESTART_DELAY_SEC}s)
────────────────────────────────────────
配置文件:     ${ENV_FILE}
覆盖方式:     POOL_HOST=xxx ./pearl_hash start
EOF
}

pearl_hash_cmd_logs() {
  local follow="false"
  local n="50"

  local args=("$@")
  local a
  for a in "${args[@]}"; do
    if [[ "$a" == "-f" ]]; then
      follow="true"
    elif [[ "$a" =~ ^[0-9]+$ ]]; then
      n="$a"
    fi
  done

  pearl_hash_ensure_dirs
  [[ -f "$LOG_FILE" ]] || {
    pearl_hash_warn "日志文件不存在：${LOG_FILE}"
    return 0
  }

  if [[ "$follow" == "true" ]]; then
    tail -n "$n" -f -- "$LOG_FILE"
  else
    tail -n "$n" -- "$LOG_FILE"
  fi
}

pearl_hash_cmd_status() {
  local brief="${1:-false}"

  pearl_hash_ensure_dirs
  pearl_hash_load_config
  pearl_hash_rotate_miner_log_if_needed

  pearl_hash_cleanup_stale_pid_file "$SUPERVISOR_PID_FILE"
  pearl_hash_cleanup_stale_pid_file "$MINER_PID_FILE"

  local supervisor_pid miner_pid
  supervisor_pid="$(pearl_hash_read_pid_file "$SUPERVISOR_PID_FILE" 2>/dev/null || true)"
  miner_pid="$(pearl_hash_read_pid_file "$MINER_PID_FILE" 2>/dev/null || true)"

  local up="0"
  if [[ -n "$miner_pid" ]] && pearl_hash_is_pid_running "$miner_pid"; then
    up="1"
  fi

  if [[ "$brief" == "true" ]]; then
    printf 'up=%s supervisor_pid=%s miner_pid=%s\n' "$up" "${supervisor_pid:-}" "${miner_pid:-}"
    return 0
  fi

  # 计算运行时长
  local etime_str=""
  if [[ "$up" == "1" ]]; then
    etime_str="$(ps -o etime= -p "$miner_pid" 2>/dev/null | head -n 1 | xargs || true)"
  fi

  # 采集 snapshot（同时写入 stats.jsonl）
  local snapshot
  snapshot="$(pearl_hash_health_collect_snapshot_json "$MINER_FLAVOR" "$LOG_FILE" "$STATS_FILE" "$WILDRIG_API_PORT" || true)"
  if [[ "${LOG_STATS_JSONL}" == "true" && -n "$snapshot" ]]; then
    pearl_hash_health_append_stats_jsonl "$STATS_FILE" "$snapshot" || true
  fi

  # 解析 API 数据
  local api_hr="" api_uptime="" api_ping="" api_temp="" api_fan="" api_power="" api_accepted="" api_rejected=""
  if [[ "$up" == "1" && "$MINER_FLAVOR" == "wildrig" && "${WILDRIG_API_PORT:-0}" != "0" ]]; then
    local api_json
    api_json="$(pearl_hash_health_wildrig_api_try_get_summary_json "$WILDRIG_API_PORT" 2 2>/dev/null || true)"
    if [[ -n "$api_json" ]]; then
      local api_fields
      api_fields="$(pearl_hash_health_parse_wildrig_api_json "$api_json" 2>/dev/null || true)"
      if [[ -n "$api_fields" ]]; then
        while IFS='=' read -r k v; do
          case "$k" in
          hashrate_total) api_hr="$v" ;;
          uptime_sec) api_uptime="$v" ;;
          pool_ping) api_ping="$v" ;;
          gpu_temp) api_temp="$v" ;;
          gpu_fan) api_fan="$v" ;;
          gpu_power) api_power="$v" ;;
          accepted) api_accepted="$v" ;;
          rejected) api_rejected="$v" ;;
          esac
        done <<<"$api_fields"
      fi
    fi
  fi

  # 温度保护状态：提取最近 3 次事件详情
  local temp_protect_info=""
  if [[ "$up" == "1" && -f "$LOG_FILE" ]]; then
    local recent_events
    recent_events="$(grep -n 'too hot! waiting to cooldown' "$LOG_FILE" 2>/dev/null | tail -3 || true)"
    if [[ -n "$recent_events" ]]; then
      while IFS= read -r event_line; do
        [[ -n "$event_line" ]] || continue
        local line_num="${event_line%%:*}"
        local event_time
        event_time="$(echo "$event_line" | grep -oP '\d{2}:\d{2}:\d{2}')"
        local gpu_id
        gpu_id="$(echo "$event_line" | grep -oP 'GPU #\d+')"

        # 从 Statistics 表格提取该 GPU 触发时的温度/功耗/算力
        local stats=""
        stats="$(head -n "$line_num" "$LOG_FILE" | grep "^ ${gpu_id#GPU }.*TH" | tail -1)"
        local temp_val="" power_val="" hash_val=""
        if [[ -n "$stats" ]]; then
          # Statistics 格式: " #0 GeForce RTX 4090  289.56 TH/s  78C  93% 449.3W 0.644 2370 10G"
          # 提取 TH/s 后的温度（°C）、功耗（W）
          hash_val="$(echo "$stats" | grep -oP '[\d.]+ TH/s')"
          hash_val="${hash_val% TH/s}"
          temp_val="$(echo "$stats" | grep -oP '\d{2,3}C')"
          temp_val="${temp_val%C}"
          power_val="$(echo "$stats" | grep -oP '[\d.]+W')"
          power_val="${power_val%W}"
        fi

        # 恢复时间
        local resume_time
        resume_time="$(tail -n +"$line_num" "$LOG_FILE" | grep -m1 'resuming mining' | grep -oP '\d{2}:\d{2}:\d{2}' || true)"

        [[ -n "$temp_protect_info" ]] && temp_protect_info="${temp_protect_info}\n"
        local detail="${event_time} ${gpu_id}"
        [[ -n "$temp_val" ]] && detail="${detail} ${temp_val}°C ${power_val}W ${hash_val}TH/s"
        detail="${detail} → 降频冷却"
        [[ -n "$resume_time" ]] && detail="${detail}（${resume_time} 恢复）"
        temp_protect_info="${temp_protect_info}    ${detail}"
      done <<<"$recent_events"
    fi
  fi

  # ───────── 输出 ─────────
  local status_label="● 运行中"
  [[ "$up" != "1" ]] && status_label="○ 已停止"

  local masked_addr
  masked_addr="$(pearl_hash_mask_middle "${USER_ADDRESS:-}" 10 6)"

  echo
  echo "  pearl_hash ${status_label}"
  echo "  ─────────────────────────────────"
  echo "  矿池:        ${POOL_HOST} (${POOL_REGION})"
  echo "  钱包:        ${masked_addr}"
  echo "  矿工:        ${WORKER_NAME}"

  if [[ "$up" == "1" ]]; then
    [[ -n "$etime_str" ]] && echo "  运行时长:    ${etime_str}"
    if [[ -n "$api_hr" ]]; then
      printf '  总算力:      %.2f TH/s\n' "$(awk "BEGIN { printf \"%.2f\", ${api_hr}/1e12 }")"
    fi
    [[ -n "$api_accepted" ]] && echo "  Shares:      ${api_accepted} accepted  ${api_rejected:-0} rejected"
    [[ -n "$api_ping" && "$api_ping" != "0" ]] && echo "  矿池延迟:    ${api_ping}ms"
    echo "  温度上限:    ${MAX_GPU_TEMP}°C"
    if [[ -n "$temp_protect_info" ]]; then
      echo "  ⚠ 温度保护（最近事件）:"
      printf '%b\n' "$temp_protect_info"
    fi
  fi

  # GPU 表格
  if [[ -n "$api_temp" ]]; then
    echo
    echo "  GPU    温度     风扇    功耗"
    echo "  ───    ────     ────    ────"
    local IFS=,
    local -a temps=() fans=() powers=()
    read -r -a temps <<<"$api_temp"
    [[ -n "$api_fan" ]] && read -r -a fans <<<"$api_fan"
    [[ -n "$api_power" ]] && read -r -a powers <<<"$api_power"

    local i
    for i in "${!temps[@]}"; do
      local t="${temps[$i]}"
      local f="${fans[$i]:--}"
      local p="${powers[$i]:--}"
      # 温度着色：>=80°C 红色
      local temp_color=""
      if [[ "$t" =~ ^[0-9]+$ ]] && (( t >= 80 )); then
        printf "  GPU#%d   \033[31m%s°C\033[0m    %s%%     %sW\n" "$i" "$t" "$f" "$p"
      else
        printf "  GPU#%d   %s°C    %s%%     %sW\n" "$i" "$t" "$f" "$p"
      fi
    done
  elif [[ "$up" == "1" ]]; then
    echo "  GPU 指标:    API 不可用，等待矿工初始化..."
  fi

  # 最近错误（只取最后 3 行）
  local fatal
  fatal="$(pearl_hash_health_extract_fatal_snippet "$LOG_FILE" || true)"
  if [[ -n "$fatal" ]]; then
    echo
    echo "  ─── 最近错误（miner.log）───"
    echo "$fatal" | tail -n 3 | while IFS= read -r line; do
      # 去掉行号前缀和 OpenCL 无意义报错
      local cleaned
      cleaned="$(echo "$line" | sed 's/^[0-9]*://')"
      if ! echo "$cleaned" | grep -q "clGetPlatformIDs"; then
        echo "  ${cleaned}"
      fi
    done
  fi

  # 收益查询
  if [[ -n "${USER_ADDRESS:-}" ]]; then
    echo
    echo "  收益查询:    $(pearl_hash_lookup_url "${USER_ADDRESS}")"
  fi
  echo
}

# monitor: 实时监控面板，封装 watch
pearl_hash_cmd_monitor() {
  local interval="${1:-5}"
  [[ "$interval" =~ ^[0-9]+$ ]] || interval=5

  if ! command -v watch >/dev/null 2>&1; then
    pearl_hash_err "缺少 watch 命令，请先安装：apt-get install procps"
    return 1
  fi

  exec watch -n "$interval" -t --color "${SCRIPT_DIR}/pearl_hash" status
}
