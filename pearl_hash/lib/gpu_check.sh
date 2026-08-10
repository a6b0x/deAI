#!/usr/bin/env bash
set -euo pipefail

# -----------------------------------------------------------------------------
# GPU 预检模块
#
# 用途：
# - start 前做“能不能挖”的快速判断：nvidia-smi 是否可用、GPU 是否存在、温度是否过高
# - 可选的“独占模式”：检测到其他 compute 进程时拒绝启动（或仅告警）
#
# 说明：
# - Pearl 算法不是 DAG/显存密集型，通常不会显存 OOM；冲突更多是 CUDA 核心算力争抢
# - 因此这里不做“显存占用阈值”拦截，只做“温度过热”硬拦截与“其他进程”提醒/拒绝
# -----------------------------------------------------------------------------

# 复用 common.sh 里统一的目录解析函数，避免本文件再复制一份。
# 注意：此处 common.sh 尚未被 source，pearl_hash_script_dir 还未定义，
# 因此用"本文件所在目录"直接拼路径加载（等价于该函数对本模块返回的结果）。
source "$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/common.sh"

# pearl_hash_has_nvidia_smi: 判断 nvidia-smi 是否可用
# 用于在查询前快速判断，避免直接调用导致报错
pearl_hash_has_nvidia_smi() {
  command -v nvidia-smi >/dev/null 2>&1
}

# pearl_hash_gpu_query_one_csv: 查询单张 GPU 的指标（CSV 一行输出）
# 注意：为减少 nvidia-smi 进程开销，通常应改用 pearl_hash_gpu_query_all_csv
# 一次取回全部再按 index 过滤（见 pearl_hash_gpu_query_all_csv 注释）。
pearl_hash_gpu_query_one_csv() {
  local gpu_id="$1"
  nvidia-smi \
    --id="$gpu_id" \
    --query-gpu=index,name,memory.used,memory.total,temperature.gpu,power.draw,fan.speed,utilization.gpu \
    --format=csv,noheader,nounits
}

# pearl_hash_gpu_query_all_csv: 一次性查询所有 GPU 指标（每卡一行 CSV）
# 相比逐卡多次调用 nvidia-smi，单次调用即可拿到全部数据，开销更小。
# 字段顺序：index,name,memory.used,memory.total,temperature.gpu,power.draw,fan.speed,utilization.gpu
# 调用方如需筛选 GPU，可在此结果上按 index 列过滤，避免多次拉起 nvidia-smi。
pearl_hash_gpu_query_all_csv() {
  nvidia-smi \
    --query-gpu=index,name,memory.used,memory.total,temperature.gpu,power.draw,fan.speed,utilization.gpu \
    --format=csv,noheader,nounits
}

# pearl_hash_gpu_list_compute_procs_csv: 列出当前占用 GPU 的计算进程（CSV）
# 用于"独占模式/冲突检测"。错误时静默返回空（|| true），不阻塞主流程。
pearl_hash_gpu_list_compute_procs_csv() {
  nvidia-smi --query-compute-apps=gpu_uuid,pid,process_name,used_memory --format=csv,noheader,nounits 2>/dev/null || true
}

# pearl_hash_gpu__parse_ignore_patterns: 解析"忽略的进程名"配置到全局数组
# 参数为逗号分隔的进程名列表（如 dcgm-exporter,Xorg），支持通配匹配。
# 结果存入全局 PEARL_HASH_GPU_IGNORE_PATTERNS，供 _proc_is_ignored 复用。
pearl_hash_gpu__parse_ignore_patterns() {
  local csv="${1:-}"
  csv="$(pearl_hash_trim "$csv")"
  if [[ -z "$csv" ]]; then
    return 0
  fi

  local IFS=,
  read -r -a PEARL_HASH_GPU_IGNORE_PATTERNS <<<"$csv"
}

# pearl_hash_gpu__proc_is_ignored: 判断某进程名是否在忽略列表中
# 用 [[ $name == $pat ]] 做 shell 通配匹配（$pat 未加引号以便展开 *）。
# 命中任一忽略模式返回 0，否则返回 1。
pearl_hash_gpu__proc_is_ignored() {
  local proc_name="$1"
  local pat
  for pat in "${PEARL_HASH_GPU_IGNORE_PATTERNS[@]:-}"; do
    pat="$(pearl_hash_trim "$pat")"
    [[ -z "$pat" ]] && continue
    if [[ "$proc_name" == $pat ]]; then
      return 0
    fi
  done
  return 1
}

# pearl_hash_gpu_check_and_warn_or_fail: 启动前的 GPU 可用性预检
# 做四件事（按优先级）：
#   1. nvidia-smi 不可用 → 跳过预检并提示（不强制失败）
#   2. 温度校验：超过 MAX_GPU_TEMP+10°C 硬拒绝启动；超过 MAX_GPU_TEMP 仅告警
#   3. 逐卡打印状态摘要（名称/显存/温度/功耗/风扇/利用率）
#   4. 冲突进程检测：扫描占用 GPU 的 compute 进程，
#      命中忽略列表（GPU_IGNORE_PROCS）的直接放行；
#      其余重度进程按 GPU_STRICT_EXCLUSIVE 决定"拒绝启动"还是"仅告警"。
# 参数：
#   $1 gpu_devices_csv     指定 GPU（空=全部）
#   $2 strict_exclusive    是否严格独占（true=检测到冲突就拒绝）
#   $3 ignore_procs_csv    忽略的进程名列表（逗号分隔，支持通配）
#   $4 max_gpu_temp        温度阈值（°C）
# 返回：0=通过/跳过；1=必须失败（格式错 / 过热 / 严格独占冲突）
pearl_hash_gpu_check_and_warn_or_fail() {
  local gpu_devices_csv="${1:-}"
  local strict_exclusive="${2:-false}"
  local ignore_procs_csv="${3:-}"
  local max_gpu_temp="${4:-85}"

  if ! pearl_hash_has_nvidia_smi; then
    pearl_hash_warn "未检测到 nvidia-smi：将跳过 GPU 预检（如需 GPU 指标/独占检测请安装 NVIDIA 驱动与工具链）"
    return 0
  fi

  # 温度阈值若不是合法数字则回退默认值，防止下面 awk/比较出错
  pearl_hash_is_number "$max_gpu_temp" || max_gpu_temp="85"

  # 解析忽略进程名列表到全局数组，供冲突检测时复用
  pearl_hash_gpu__parse_ignore_patterns "$ignore_procs_csv"

  # 一次性取回所有 GPU 指标（避免逐卡多次调 nvidia-smi）
  local query_csv
  query_csv="$(pearl_hash_gpu_query_all_csv 2>/dev/null || true)"
  if [[ -z "$query_csv" ]]; then
    pearl_hash_warn "nvidia-smi 可执行但无法返回 GPU 列表：将跳过 GPU 预检"
    return 0
  fi

  # 解析 GPU_DEVICES，得到需要重点检查的 GPU index 集合
  local selected=()
  if [[ -n "${gpu_devices_csv:-}" ]]; then
    pearl_hash_parse_csv_ints "$gpu_devices_csv" || {
      pearl_hash_err "GPU_DEVICES 格式错误：应为逗号分隔的数字，例如 0,1"
      return 1
    }
    local IFS=,
    read -r -a selected <<<"$(pearl_hash_trim "$gpu_devices_csv")"
  fi

  local line
  while IFS= read -r line; do
    line="$(pearl_hash_trim "$line")"
    [[ -z "$line" ]] && continue

    # 按查询字段顺序拆列
    local idx name mem_used mem_total temp power fan util
    IFS=, read -r idx name mem_used mem_total temp power fan util <<<"$line"
    idx="$(pearl_hash_trim "$idx")"
    name="$(pearl_hash_trim "$name")"
    mem_used="$(pearl_hash_trim "$mem_used")"
    mem_total="$(pearl_hash_trim "$mem_total")"
    temp="$(pearl_hash_trim "$temp")"
    power="$(pearl_hash_trim "$power")"
    fan="$(pearl_hash_trim "$fan")"
    util="$(pearl_hash_trim "$util")"

    # 若指定了 GPU_DEVICES，则只检查其中命中的卡
    if [[ "${#selected[@]}" -gt 0 ]]; then
      local hit="false"
      local s
      for s in "${selected[@]}"; do
        s="$(pearl_hash_trim "$s")"
        [[ "$s" == "$idx" ]] && hit="true" && break
      done
      [[ "$hit" == "true" ]] || continue
    fi

    # 温度校验：硬拒绝阈值 = 配置阈值 + 10°C，避免偶发尖峰误杀
    if pearl_hash_is_number "$temp"; then
      local hard_limit
      hard_limit="$(awk -v t="$max_gpu_temp" 'BEGIN { printf "%.0f", t+10 }')"
      if (( temp > hard_limit )); then
        pearl_hash_err "GPU#${idx} 温度过高：${temp}°C（阈值 ${max_gpu_temp}°C，硬拒绝 >${hard_limit}°C）。请先降温或暂停其他负载。"
        return 1
      fi
      if (( temp > max_gpu_temp )); then
        pearl_hash_warn "GPU#${idx} 温度偏高：${temp}°C（阈值 ${max_gpu_temp}°C）"
      fi
    fi

    pearl_hash_log "GPU#${idx} ${name} | mem ${mem_used}/${mem_total} MiB | temp ${temp}°C | power ${power}W | fan ${fan}% | util ${util}%"
  done <<<"$query_csv"

  # 冲突进程检测
  local procs_csv
  procs_csv="$(pearl_hash_gpu_list_compute_procs_csv)"
  if [[ -z "$procs_csv" ]]; then
    return 0
  fi

  local conflicts=()
  while IFS= read -r line; do
    line="$(pearl_hash_trim "$line")"
    [[ -z "$line" ]] && continue

    local gpu_uuid pid proc_name used_mem
    IFS=, read -r gpu_uuid pid proc_name used_mem <<<"$line"
    pid="$(pearl_hash_trim "$pid")"
    proc_name="$(pearl_hash_trim "$proc_name")"
    used_mem="$(pearl_hash_trim "$used_mem")"

    # 忽略无 PID / 无进程名的残缺行
    [[ -n "$pid" ]] || continue
    [[ -n "$proc_name" ]] || continue

    # 命中忽略列表（监控容器/Xorg 等轻量进程）则放行
    if pearl_hash_gpu__proc_is_ignored "$proc_name"; then
      continue
    fi
    conflicts+=("pid=${pid} name=${proc_name} mem=${used_mem}MiB")
  done <<<"$procs_csv"

  # 存在未忽略的冲突进程时，按独占开关决定拒绝 or 告警
  if [[ "${#conflicts[@]}" -gt 0 ]]; then
    if [[ "$strict_exclusive" == "true" ]]; then
      pearl_hash_err "检测到其他 GPU compute 进程（严格独占模式已开启，拒绝启动）：${conflicts[*]}"
      return 1
    fi
    pearl_hash_warn "检测到其他 GPU compute 进程（可能存在算力争抢，建议先 pause/stop 其他任务）：${conflicts[*]}"
  fi

  return 0
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  pearl_hash_warn "gpu_check.sh 是模块文件，建议由入口脚本 source 后调用 pearl_hash_gpu_check_and_warn_or_fail"
fi
