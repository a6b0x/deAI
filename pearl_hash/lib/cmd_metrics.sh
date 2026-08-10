#!/usr/bin/env bash
set -euo pipefail

# -----------------------------------------------------------------------------
# cmd_metrics.sh —— metrics 命令模块（Prometheus 格式输出）
# -----------------------------------------------------------------------------

source "$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/common.sh"

pearl_hash_cmd_metrics() {
  pearl_hash_ensure_dirs
  pearl_hash_load_config
  pearl_hash_cleanup_stale_pid_file "$MINER_PID_FILE"

  local miner_pid
  miner_pid="$(pearl_hash_read_pid_file "$MINER_PID_FILE" 2>/dev/null || true)"

  local up="0"
  if [[ -n "$miner_pid" ]] && pearl_hash_is_pid_running "$miner_pid"; then
    up="1"
  fi

  local snapshot
  snapshot="$(pearl_hash_health_collect_snapshot_json "$MINER_FLAVOR" "$LOG_FILE" "$STATS_FILE" "$WILDRIG_API_PORT" || true)"
  if [[ "${LOG_STATS_JSONL}" == "true" && -n "$snapshot" ]]; then
    pearl_hash_health_append_stats_jsonl "$STATS_FILE" "$snapshot" || true
  fi

  local hashrate_total=""
  local accepted=""
  local rejected=""

  if command -v python3 >/dev/null 2>&1 && [[ -n "$snapshot" ]]; then
    read -r hashrate_total accepted rejected < <(python3 - "$snapshot" <<'PY'
import json,sys
data=json.loads(sys.argv[1])
print(data.get("hashrate_total_hs",""), data.get("accepted",""), data.get("rejected",""))
PY
)
  fi

  cat <<EOF
# HELP pearl_hash_miner_up Miner process running (1=running, 0=stopped)
# TYPE pearl_hash_miner_up gauge
pearl_hash_miner_up ${up}
EOF

  if [[ -n "$miner_pid" ]]; then
    cat <<EOF
# HELP pearl_hash_pid Miner process ID
# TYPE pearl_hash_pid gauge
pearl_hash_pid ${miner_pid}
EOF
  fi

  cat <<EOF
# HELP pearl_hash_miner_flavor Miner flavor (1=pearl legacy, 2=wildrig)
# TYPE pearl_hash_miner_flavor gauge
pearl_hash_miner_flavor{name="${MINER_FLAVOR}"} $( [[ "$MINER_FLAVOR" == "pearl" ]] && echo 1 || echo 2 )
EOF

  if [[ -n "$hashrate_total" ]]; then
    cat <<EOF
# HELP pearl_hash_hashrate_hs Hashrate in H/s
# TYPE pearl_hash_hashrate_hs gauge
pearl_hash_hashrate_hs{gpu="total"} ${hashrate_total}
EOF
  fi

  if [[ -n "$accepted" || -n "$rejected" ]]; then
    cat <<EOF
# HELP pearl_hash_shares_total Total shares
# TYPE pearl_hash_shares_total counter
EOF
    [[ -n "$accepted" ]] && echo "pearl_hash_shares_total{result=\"accepted\"} ${accepted}"
    [[ -n "$rejected" ]] && echo "pearl_hash_shares_total{result=\"rejected\"} ${rejected}"
  fi

  # GPU 指标：优先 WildRig API，降级 nvidia-smi
  local api_gpu_ok=""
  if [[ "$up" == "1" && "$MINER_FLAVOR" == "wildrig" && "${WILDRIG_API_PORT:-0}" != "0" ]]; then
    local api_json
    api_json="$(pearl_hash_health_wildrig_api_try_get_summary_json "$WILDRIG_API_PORT" 2 2>/dev/null || true)"
    if [[ -n "$api_json" ]]; then
      local api_fields
      api_fields="$(pearl_hash_health_parse_wildrig_api_json "$api_json" 2>/dev/null || true)"
      if [[ -n "$api_fields" ]]; then
        local api_temp="" api_fan="" api_power="" api_hashrate="" api_ping="" api_uptime=""
        while IFS='=' read -r k v; do
          case "$k" in
          gpu_temp) api_temp="$v" ;;
          gpu_fan) api_fan="$v" ;;
          gpu_power) api_power="$v" ;;
          hashrate_total) api_hashrate="$v" ;;
          pool_ping) api_ping="$v" ;;
          uptime_sec) api_uptime="$v" ;;
          esac
        done <<<"$api_fields"

        if [[ -n "$api_temp" ]]; then
          api_gpu_ok="1"
          echo '# HELP pearl_hash_gpu_temperature_celsius GPU temperature (from WildRig API)'
          echo '# TYPE pearl_hash_gpu_temperature_celsius gauge'
          echo '# HELP pearl_hash_gpu_power_watts GPU power draw (from WildRig API)'
          echo '# TYPE pearl_hash_gpu_power_watts gauge'
          echo '# HELP pearl_hash_gpu_fan_percent GPU fan speed (from WildRig API)'
          echo '# TYPE pearl_hash_gpu_fan_percent gauge'

          local IFS=,
          local -a temps=() fans=() powers=()
          read -r -a temps <<<"$api_temp"
          [[ -n "$api_fan" ]] && read -r -a fans <<<"$api_fan"
          [[ -n "$api_power" ]] && read -r -a powers <<<"$api_power"

          local i
          for i in "${!temps[@]}"; do
            echo "pearl_hash_gpu_temperature_celsius{gpu=\"${i}\"} ${temps[$i]}"
            echo "pearl_hash_gpu_power_watts{gpu=\"${i}\"} ${powers[$i]:-0}"
            echo "pearl_hash_gpu_fan_percent{gpu=\"${i}\"} ${fans[$i]:-0}"
          done

          # API 提供的额外指标
          [[ -n "$api_hashrate" ]] && echo "# HELP pearl_hash_hashrate_hs_api Hashrate from API" && echo "# TYPE pearl_hash_hashrate_hs_api gauge" && echo "pearl_hash_hashrate_hs_api ${api_hashrate}"
          [[ -n "$api_ping" ]] && echo "# HELP pearl_hash_pool_ping_ms Pool latency" && echo "# TYPE pearl_hash_pool_ping_ms gauge" && echo "pearl_hash_pool_ping_ms ${api_ping}"
          [[ -n "$api_uptime" ]] && echo "# HELP pearl_hash_uptime_seconds Miner uptime" && echo "# TYPE pearl_hash_uptime_seconds gauge" && echo "pearl_hash_uptime_seconds ${api_uptime}"
        fi
      fi
    fi
  fi

  if [[ -z "$api_gpu_ok" ]] && pearl_hash_has_nvidia_smi; then
    echo '# HELP pearl_hash_gpu_temperature_celsius GPU temperature (from nvidia-smi)'
    echo '# TYPE pearl_hash_gpu_temperature_celsius gauge'
    echo '# HELP pearl_hash_gpu_power_watts GPU power draw (from nvidia-smi)'
    echo '# TYPE pearl_hash_gpu_power_watts gauge'
    echo '# HELP pearl_hash_gpu_utilization_percent GPU utilization (from nvidia-smi)'
    echo '# TYPE pearl_hash_gpu_utilization_percent gauge'

    local gpu_devices_csv
    gpu_devices_csv="$(pearl_hash_trim "${GPU_DEVICES:-}")"
    local -a want=()
    if [[ -n "$gpu_devices_csv" ]]; then
      local IFS=,
      read -r -a want <<<"$gpu_devices_csv"
    fi

    local lines
    lines="$(pearl_hash_gpu_query_all_csv 2>/dev/null || true)"

    local line
    while IFS= read -r line; do
      line="$(pearl_hash_trim "$line")"
      [[ -n "$line" ]] || continue
      local idx name mem_used mem_total temp power fan util
      IFS=, read -r idx name mem_used mem_total temp power fan util <<<"$line"
      idx="$(pearl_hash_trim "$idx")"
      temp="$(pearl_hash_trim "$temp")"
      power="$(pearl_hash_trim "$power")"
      util="$(pearl_hash_trim "$util")"
      [[ -n "$idx" ]] || continue

      if [[ "${#want[@]}" -gt 0 ]]; then
        local w hitg=""
        for w in "${want[@]}"; do
          w="$(pearl_hash_trim "$w")"
          [[ "$w" == "$idx" ]] && hitg="1" && break
        done
        [[ -n "$hitg" ]] || continue
      fi

      [[ -n "$temp" ]] || temp="0"
      [[ -n "$power" ]] || power="0"
      [[ -n "$util" ]] || util="0"
      echo "pearl_hash_gpu_temperature_celsius{gpu=\"${idx}\"} ${temp}"
      echo "pearl_hash_gpu_power_watts{gpu=\"${idx}\"} ${power}"
      echo "pearl_hash_gpu_utilization_percent{gpu=\"${idx}\"} ${util}"
    done <<<"$lines"
  fi

  # 历史聚合指标
  local hr1 hr6 hr24 rr
  hr1="$(pearl_hash_health_compute_hashrate_avg_hs "$STATS_FILE" 3600 2>/dev/null || true)"
  hr6="$(pearl_hash_health_compute_hashrate_avg_hs "$STATS_FILE" 21600 2>/dev/null || true)"
  hr24="$(pearl_hash_health_compute_hashrate_avg_hs "$STATS_FILE" 86400 2>/dev/null || true)"
  rr="$(pearl_hash_health_compute_reject_rate "$STATS_FILE" 86400 2>/dev/null || true)"

  if [[ -n "$hr1" || -n "$hr6" || -n "$hr24" ]]; then
    echo '# HELP pearl_hash_hashrate_avg_hs Average hashrate over window'
    echo '# TYPE pearl_hash_hashrate_avg_hs gauge'
    [[ -n "$hr1" ]] && echo "pearl_hash_hashrate_avg_hs{window=\"1h\"} ${hr1}"
    [[ -n "$hr6" ]] && echo "pearl_hash_hashrate_avg_hs{window=\"6h\"} ${hr6}"
    [[ -n "$hr24" ]] && echo "pearl_hash_hashrate_avg_hs{window=\"24h\"} ${hr24}"
  fi
  if [[ -n "$rr" ]]; then
    echo '# HELP pearl_hash_reject_rate_percent Reject rate over 24h (percent)'
    echo '# TYPE pearl_hash_reject_rate_percent gauge'
    echo "pearl_hash_reject_rate_percent ${rr}"
  fi
}
