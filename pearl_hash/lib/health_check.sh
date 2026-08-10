#!/usr/bin/env bash
set -euo pipefail

# -----------------------------------------------------------------------------
# 健康检查 / 数据采样模块
#
# 核心职责：
# - 从 WildRig API（如启用）或 miner.log 中提取“总算力/accepted/rejected”等关键指标
# - 生成一行 JSON（snapshot），供 status/metrics 使用，并可追加写入 stats.jsonl
#
# 设计取舍：
# - WildRig API 的具体端点在不同版本可能有差异，因此这里采用“多端点尝试 + 容错解析”
# - API 不可用时自动降级为解析日志（但日志格式更脆弱）
# -----------------------------------------------------------------------------

# 复用 common.sh 里统一的目录解析函数，避免本文件再复制一份。
# 注意：此处 common.sh 尚未被 source，pearl_hash_script_dir 还未定义，
# 因此用"本文件所在目录"直接拼路径加载（等价于该函数对本模块返回的结果）。
source "$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/common.sh"

# pearl_hash__have_python3: 判断 python3 是否可用（快照解析依赖）
pearl_hash__have_python3() {
  command -v python3 >/dev/null 2>&1
}

# pearl_hash_hashrate_unit_to_multiplier: 将算力单位映射为倍数（字符串形式）
# 例如 "MH/s" → "1e6"，"TH/s" → "1e12"；未知单位返回 "0"（调用方据此判失败）。
# 返回倍数给 awk 直接做浮点运算，避免 bash 整数溢出。
pearl_hash_hashrate_unit_to_multiplier() {
  local unit="$1"
  case "$unit" in
  H|H/s|Hs|hash/s) printf '1' ;;
  KH|KH/s|kH|kH/s|khs|KHs) printf '1e3' ;;
  MH|MH/s|mH|mH/s|mhs|MHs) printf '1e6' ;;
  GH|GH/s|gH|gH/s|ghs|GHs) printf '1e9' ;;
  TH|TH/s|tH|tH/s|ths|THs) printf '1e12' ;;
  PH|PH/s|pH|pH/s|phs|PHs) printf '1e15' ;;
  *) printf '0' ;;
  esac
}

# pearl_hash_parse_hashrate_to_hs: 把 "数值+单位" 的算力换算为 H/s（整数）
# 参数：$1 数值，$2 单位。任一非法返回 1。
pearl_hash_parse_hashrate_to_hs() {
  local value="$1"
  local unit="$2"
  value="$(pearl_hash_trim "$value")"
  unit="$(pearl_hash_trim "$unit")"
  pearl_hash_is_number "$value" || return 1

  local mul
  mul="$(pearl_hash_hashrate_unit_to_multiplier "$unit")"
  [[ "$mul" != "0" ]] || return 1
  awk -v v="$value" -v m="$mul" 'BEGIN { printf "%.0f", v*m }'
}

# pearl_hash_extract_hashrate_from_line: 从一行日志中提取"算力值+单位"并换算为 H/s
# 用 sed 正则抓取 "数字 + 可选 KMGTP 前缀 H/s 或 H"，再交给 parse 换算。
# 提取失败返回 1（调用方自行降级）。
pearl_hash_extract_hashrate_from_line() {
  local line="$1"
  local out
  out="$(echo "$line" | sed -nE 's/.*([0-9]+([.][0-9]+)?)\s*([KMGTP]?H\/s|[KMGTP]?H).*/\1 \3/p' | head -n 1 || true)"
  if [[ -z "$out" ]]; then
    return 1
  fi
  local v u
  read -r v u <<<"$out"
  pearl_hash_parse_hashrate_to_hs "$v" "$u"
}

# pearl_hash_read_tail_lines: 读取日志末尾 N 行
# 参数：$1 文件，$2 行数（默认 200）。文件不存在返回空串。
pearl_hash_read_tail_lines() {
  local file="$1"
  local n="${2:-200}"
  [[ -f "$file" ]] || return 0
  tail -n "$n" -- "$file" 2>/dev/null || true
}

# pearl_hash_health_wildrig_api_try_get_summary_json: 尝试从 WildRig HTTP API 取状态
# WildRig 0.49.9 API 路径是 "/"，返回完整 JSON（包含 hashrate/hwmon/results/connection）
# 参数：$1 端口；$2 超时秒数（默认 2）
pearl_hash_health_wildrig_api_try_get_summary_json() {
  local port="$1"
  local timeout_sec="${2:-2}"
  local url="http://127.0.0.1:${port}/"
  local body
  body="$(pearl_hash_http_get "$url" "$timeout_sec" 2>/dev/null || true)"
  if [[ -n "$body" ]]; then
    printf '%s' "$body"
    return 0
  fi
  return 1
}

# pearl_hash_health_parse_wildrig_api_json: 从 WildRig API JSON 中提取指标
# 使用 awk 正则解析，不依赖 python3
# API 数据结构（WildRig 0.49.9）：
#   hashrate.total[0]  = 10s 总算力（H/s）
#   hwmon.temp[]       = 每 GPU 温度
#   hwmon.fan[]        = 每 GPU 风扇转速
#   hwmon.power[]      = 每 GPU 功耗（W）
#   results.shares_good = 总 accepted 数
#   results.shares_rejected = 每 GPU 拒绝数数组
#   connection.ping    = 矿池延迟（ms）
#   uptime             = 运行秒数
# 输出 key=value 行，调用方 eval 或逐行解析
pearl_hash_health_parse_wildrig_api_json() {
  local json="$1"

  local hashrate_total=""
  local accepted=""
  local rejected=""
  local gpu_count=0
  local gpu_temp="" gpu_fan="" gpu_power=""
  local pool_ping="" uptime_sec=""

  # 提取 total hashrate（10s 窗口）：匹配 "total": [数字 模式
  hashrate_total="$(echo "$json" | awk '
    /"total"[[:space:]]*:[[:space:]]*\[/ {
      # 下一行就是数字
      getline
      gsub(/[^0-9]/, "", $0)
      if ($0 != "") { print $0; exit }
    }
  ' 2>/dev/null || true)"

  # 提取 shares_good（总 accepted）
  accepted="$(echo "$json" | awk -F'[:,]' '
    /"shares_good"/ { gsub(/[^0-9]/,"",$0); print $0; exit }
  ' 2>/dev/null || true)"

  # 提取 shares_rejected 数组总和
  rejected="$(echo "$json" | awk '
    /"shares_rejected"/ { in_rej=1; next }
    in_rej && /\]/ { exit }
    in_rej && /[0-9]/ { gsub(/[^0-9]/,"",$0); if($0!="") sum+=$0 }
    END { if(sum) print sum }
  ' 2>/dev/null || true)"

  # 提取 hwmon 各数组
  gpu_temp="$(echo "$json" | awk '
    /"temp"/ { in_t=1; next }
    in_t && /\]/ { exit }
    in_t && /[0-9]/ { gsub(/[^0-9]/,"",$0); if($0!="") { if(out!="") out=out","; out=out $0 } }
    END { print out }
  ' 2>/dev/null || true)"

  gpu_fan="$(echo "$json" | awk '
    /"fan"/ { in_f=1; next }
    in_f && /\]/ { exit }
    in_f && /[0-9]/ { gsub(/[^0-9]/,"",$0); if($0!="") { if(out!="") out=out","; out=out $0 } }
    END { print out }
  ' 2>/dev/null || true)"

  gpu_power="$(echo "$json" | awk '
    /"power"/ { in_p=1; next }
    in_p && /\]/ { exit }
    in_p && /[0-9]/ { gsub(/[^0-9]/,"",$0); if($0!="") { if(out!="") out=out","; out=out $0 } }
    END { print out }
  ' 2>/dev/null || true)"

  # 提取 pool ping 和 uptime
  pool_ping="$(echo "$json" | awk -F'[:,]' '
    /"ping"/ { gsub(/[^0-9]/,"",$0); print $0; exit }
  ' 2>/dev/null || true)"

  uptime_sec="$(echo "$json" | awk -F'[:,]' '
    /"uptime"/ { gsub(/[^0-9]/,"",$0); print $0; exit }
  ' 2>/dev/null || true)"

  local gpu_count_num=0
  if [[ -n "$gpu_temp" ]]; then
    gpu_count_num="$(echo "$gpu_temp" | tr ',' '\n' | wc -l | xargs || true)"
  fi

  # 输出 key=value 格式（每行一个字段）
  [[ -n "$hashrate_total" ]] && printf 'hashrate_total=%s\n' "$hashrate_total"
  [[ -n "$accepted" ]] && printf 'accepted=%s\n' "$accepted"
  [[ -n "$rejected" ]] && printf 'rejected=%s\n' "$rejected"
  [[ -n "$gpu_temp" ]] && printf 'gpu_temp=%s\n' "$gpu_temp"
  [[ -n "$gpu_fan" ]] && printf 'gpu_fan=%s\n' "$gpu_fan"
  [[ -n "$gpu_power" ]] && printf 'gpu_power=%s\n' "$gpu_power"
  [[ -n "$pool_ping" ]] && printf 'pool_ping=%s\n' "$pool_ping"
  [[ -n "$uptime_sec" ]] && printf 'uptime_sec=%s\n' "$uptime_sec"
  [[ -n "$gpu_count_num" ]] && printf 'gpu_count=%s\n' "$gpu_count_num"
}

# pearl_hash_health_parse_last_stats_jsonl: 读取 stats.jsonl 最后一行
# 供聚合/对比历史快照使用。文件不存在返回 1。
pearl_hash_health_parse_last_stats_jsonl() {
  local stats_file="$1"
  [[ -f "$stats_file" ]] || return 1
  tail -n 1 -- "$stats_file" 2>/dev/null || true
}

# pearl_hash_health_read_tail_bytes: 读取文件末尾指定字节数（性能优化用）
# 对大日志做正则扫描时，只 tail 尾部一小段而不是全文件 grep，显著降低 IO。
# 参数：$1 文件；$2 字节数（默认 262144 = 256KB）
pearl_hash_health_read_tail_bytes() {
  local file="$1"
  local bytes="${2:-262144}"
  [[ -f "$file" ]] || return 0
  tail -c "$bytes" -- "$file" 2>/dev/null || true
}

# pearl_hash_health_extract_fatal_snippet: 提取最近 5 条致命/错误日志片段
# 性能优化：只对日志末尾 256KB 做 grep，避免对大文件全量扫描。
# 输出带行号的匹配行，供 status 展示最近错误。
pearl_hash_health_extract_fatal_snippet() {
  local log_file="$1"
  [[ -f "$log_file" ]] || return 0
  pearl_hash_health_read_tail_bytes "$log_file" 262144 \
    | grep -nE 'FATAL|Error|Connection refused' 2>/dev/null | tail -n 5 || true
}

# pearl_hash_health_collect_snapshot_json: 收集一次指标快照（输出一行 JSON）
# 数据来源优先级：
#   1. WildRig HTTP API（miner_flavor=wildrig 且端口非 0 时优先）
#   2. 降级解析 miner.log 末尾（算力摘要行 / accepted/rejected 计数）
# 输出形如：{"ts":"...","hashrate_total_hs":...,"accepted":...,"rejected":...}
# 该快照用于 status/metrics 展示，也会落盘到 stats.jsonl 供历史聚合。
# 参数：
#   $1 miner_flavor       pearl / wildrig
#   $2 log_file           miner.log 路径
#   $3 stats_file         stats.jsonl 路径（当前仅用于一致性，解析仍在日志/API）
#   $4 wildrig_api_port   WildRig API 端口（0=关闭）
pearl_hash_health_collect_snapshot_json() {
  local miner_flavor="$1"
  local log_file="$2"
  local stats_file="$3"
  local wildrig_api_port="${4:-0}"

  local ts
  ts="$(date --iso-8601=seconds)"

  local hashrate_total_hs=""
  local accepted=""
  local rejected=""
  local gpu_temp=""
  local gpu_fan=""
  local gpu_power=""
  local pool_ping=""
  local uptime_sec=""

  if [[ "$miner_flavor" == "wildrig" && "${wildrig_api_port:-0}" != "0" ]]; then
    local json
    json="$(pearl_hash_health_wildrig_api_try_get_summary_json "$wildrig_api_port" 2 || true)"
    if [[ -n "$json" ]]; then
      local fields
      fields="$(pearl_hash_health_parse_wildrig_api_json "$json" 2>/dev/null || true)"
      if [[ -n "$fields" ]]; then
        while IFS='=' read -r key val; do
          case "$key" in
          hashrate_total) hashrate_total_hs="$val" ;;
          accepted) accepted="$val" ;;
          rejected) rejected="$val" ;;
          gpu_temp) gpu_temp="$val" ;;
          gpu_fan) gpu_fan="$val" ;;
          gpu_power) gpu_power="$val" ;;
          pool_ping) pool_ping="$val" ;;
          uptime_sec) uptime_sec="$val" ;;
          esac
        done <<<"$fields"
      fi
    fi
  fi

  if [[ -z "$hashrate_total_hs" && -f "$log_file" ]]; then
    local tail
    tail="$(pearl_hash_read_tail_lines "$log_file" 400)"
    if [[ -n "$tail" ]]; then
      local line
      while IFS= read -r line; do
        if [[ "$miner_flavor" == "pearl" && "$line" == *"Hashrate Total"* ]]; then
          hashrate_total_hs="$(pearl_hash_extract_hashrate_from_line "$line" 2>/dev/null || true)"
          [[ -n "$hashrate_total_hs" ]] && break
        fi
        if [[ "$miner_flavor" == "wildrig" && "$line" == *"speed"* ]]; then
          hashrate_total_hs="$(pearl_hash_extract_hashrate_from_line "$line" 2>/dev/null || true)"
          [[ -n "$hashrate_total_hs" ]] && break
        fi
      done <<<"$(echo "$tail" | tac)"
    fi
  fi

  # 若 API 未提供 accepted/rejected，降级从日志末尾提取
  # 性能优化：只对末尾 256KB 做 grep，而非全文件扫描
  if [[ -z "$accepted" && -f "$log_file" ]]; then
    accepted="$(pearl_hash_health_read_tail_bytes "$log_file" 262144 \
      | grep -Eo 'accepted[^0-9]*[0-9]+' 2>/dev/null | tail -n 1 | grep -Eo '[0-9]+' || true)"
  fi
  if [[ -z "$rejected" && -f "$log_file" ]]; then
    rejected="$(pearl_hash_health_read_tail_bytes "$log_file" 262144 \
      | grep -Eo 'rejected[^0-9]*[0-9]+' 2>/dev/null | tail -n 1 | grep -Eo '[0-9]+' || true)"
  fi

  # 组装 JSON：仅包含有值的字段，保证输出始终是合法 JSON 对象
  local json
  json="{\"ts\":\"${ts}\""
  [[ -n "$hashrate_total_hs" ]] && json="${json},\"hashrate_total_hs\":${hashrate_total_hs}"
  [[ -n "$accepted" ]] && json="${json},\"accepted\":${accepted}"
  [[ -n "$rejected" ]] && json="${json},\"rejected\":${rejected}"
  [[ -n "$gpu_temp" ]] && json="${json},\"gpu_temp\":\"${gpu_temp}\""
  [[ -n "$gpu_fan" ]] && json="${json},\"gpu_fan\":\"${gpu_fan}\""
  [[ -n "$gpu_power" ]] && json="${json},\"gpu_power\":\"${gpu_power}\""
  [[ -n "$pool_ping" ]] && json="${json},\"pool_ping\":${pool_ping}"
  [[ -n "$uptime_sec" ]] && json="${json},\"uptime_sec\":${uptime_sec}"
  json="${json}}"

  printf '%s' "$json"
}

# pearl_hash_health_append_stats_jsonl: 追加一行快照到 stats.jsonl
# 自动确保目录存在，逐行追加（JSONL 格式：一行一个 JSON 对象）
pearl_hash_health_append_stats_jsonl() {
  local stats_file="$1"
  local json_line="$2"

  local dir
  dir="$(dirname -- "$stats_file")"
  pearl_hash_mkdirp "$dir"
  printf '%s\n' "$json_line" >>"$stats_file"
}

# pearl_hash_health_extract_fatal_snippet: 提取最近 5 条致命/错误日志片段
# 性能优化：只对日志末尾 256KB 做 grep，避免对大文件全量扫描。
# 输出带行号的匹配行，供 status 展示最近错误。
pearl_hash_health_extract_fatal_snippet() {
  local log_file="$1"
  [[ -f "$log_file" ]] || return 0
  pearl_hash_health_read_tail_bytes "$log_file" 262144 \
    | grep -nE 'FATAL|Error|Connection refused' 2>/dev/null | tail -n 5 || true
}

# pearl_hash_health_compute_hashrate_avg_hs: 从 stats.jsonl 时间窗计算平均算力
# 聚合 note.md 要求的 1h/6h/24h 平均算力。用 python3 处理时间窗口与浮点均值，
# 避免 bash 对 ISO-8601 时间做解析的复杂性。
# 参数：$1 stats.jsonl 路径；$2 时间窗口秒数（如 3600 / 21600 / 86400）
# 输出：窗口内有数据则输出整数均值（H/s），否则输出空串并返回 1
pearl_hash_health_compute_hashrate_avg_hs() {
  local stats_file="$1"
  local window_sec="${2:-3600}"
  [[ -f "$stats_file" ]] || return 1
  pearl_hash__have_python3 || return 1

  python3 - "$stats_file" "$window_sec" <<'PY'
import json,sys,datetime
f=sys.argv[1]
win=int(sys.argv[2])
now=datetime.datetime.now(datetime.timezone.utc).astimezone()
vals=[]
try:
    for line in open(f,encoding="utf-8"):
        line=line.strip()
        if not line:
            continue
        try:
            o=json.loads(line)
        except Exception:
            continue
        ts=o.get("ts")
        hr=o.get("hashrate_total_hs")
        if not ts or not isinstance(hr,(int,float)) or hr<=0:
            continue
        try:
            t=datetime.datetime.fromisoformat(ts)
        except Exception:
            continue
        if (now-t).total_seconds() <= win:
            vals.append(hr)
except Exception:
    pass
if not vals:
    sys.exit(1)
print("%.0f" % (sum(vals)/len(vals)), end="")
PY
}

# pearl_hash_health_compute_reject_rate: 从 stats.jsonl 时间窗计算拒绝率
# 参数：$1 stats.jsonl 路径；$2 时间窗口秒数
# 输出：拒绝率百分比字符串（如 0.35），窗口内无 shares 数据时返回 1
pearl_hash_health_compute_reject_rate() {
  local stats_file="$1"
  local window_sec="${2:-3600}"
  [[ -f "$stats_file" ]] || return 1
  pearl_hash__have_python3 || return 1

  python3 - "$stats_file" "$window_sec" <<'PY'
import json,sys,datetime
f=sys.argv[1]
win=int(sys.argv[2])
now=datetime.datetime.now(datetime.timezone.utc).astimezone()
acc=0
rej=0
try:
    for line in open(f,encoding="utf-8"):
        line=line.strip()
        if not line:
            continue
        try:
            o=json.loads(line)
        except Exception:
            continue
        ts=o.get("ts")
        if not ts:
            continue
        try:
            t=datetime.datetime.fromisoformat(ts)
        except Exception:
            continue
        if (now-t).total_seconds() > win:
            continue
        acc += int(o.get("accepted") or 0)
        rej += int(o.get("rejected") or 0)
except Exception:
    pass
if acc+rej == 0:
    sys.exit(1)
print("%.2f" % (rej*100.0/(acc+rej)), end="")
PY
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  pearl_hash_warn "health_check.sh 是模块文件，建议由入口脚本 source 后调用 pearl_hash_health_collect_snapshot_json / pearl_hash_health_append_stats_jsonl"
fi
