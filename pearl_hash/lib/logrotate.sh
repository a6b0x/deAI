#!/usr/bin/env bash
set -euo pipefail

# 复用 common.sh 里统一的目录解析函数，避免本文件再复制一份。
# 注意：此处 common.sh 尚未被 source，pearl_hash_script_dir 还未定义，
# 因此用"本文件所在目录"直接拼路径加载（等价于该函数对本模块返回的结果）。
source "$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/common.sh"

# pearl_hash_rotate_logs: 对日志文件做"按大小轮转 + 滚动归档 + 可选压缩"
# 轮转规则（keep 份历史）：
#   miner.log 超限后 →
#     删除最旧 miner.log.{keep}.gz →
#     依次后移：.6.gz→.7.gz ... .1.gz→.2.gz →
#     miner.log 本身改名为 miner.log.1 →
#     LOG_COMPRESS=true 时把 miner.log.1 gzip 成 miner.log.1.gz
# 参数：
#   $1 log_file      要轮转的日志文件绝对路径
#   $2 max_size_mb   超过此大小（MB）触发轮转
#   $3 keep          保留的历史归档份数
#   $4 compress      是否 gzip 压缩归档（默认 true）
# 返回：0=无需轮转或轮转成功；1=参数非法
pearl_hash_rotate_logs() {
  local log_file="$1"
  local max_size_mb="$2"
  local keep="$3"
  local compress="${4:-true}"

  # 文件不存在或参数非法直接返回
  [[ -f "$log_file" ]] || return 0
  pearl_hash_is_number "$max_size_mb" || return 1
  [[ "$keep" =~ ^[0-9]+$ ]] || return 1
  (( keep >= 1 )) || keep=1

  # 把 MB 转成字节数（用 awk 处理浮点，避免 bash 整数截断）
  local max_bytes
  max_bytes="$(awk -v mb="$max_size_mb" 'BEGIN { printf "%.0f", mb*1024*1024 }')"

  # 读取当前文件大小，未超限则不轮转（避免频繁 IO）
  local size
  size="$(stat -c '%s' -- "$log_file" 2>/dev/null || echo 0)"
  [[ "$size" =~ ^[0-9]+$ ]] || size=0
  (( size > max_bytes )) || return 0

  local dir base
  dir="$(dirname -- "$log_file")"
  base="$(basename -- "$log_file")"

  # 先删除最旧的归档，腾出位置
  local oldest="${dir}/${base}.${keep}.gz"
  rm -f -- "$oldest"

  # 从大到小依次改名：.6.gz → .7.gz, .5.gz → .6.gz ...
  # 注意从 keep-1 往下循环，避免改名覆盖未读的源文件
  local i
  for (( i=keep-1; i>=1; i-- )); do
    local srcf="${dir}/${base}.${i}.gz"
    local dstf="${dir}/${base}.$((i+1)).gz"
    [[ -f "$srcf" ]] && mv -f -- "$srcf" "$dstf"
  done

  # 当前日志 → .1，并新建空文件让 miner 继续写入
  local rotated="${dir}/${base}.1"
  mv -f -- "$log_file" "$rotated"
  : >"$log_file"

  # 按配置决定压缩归档或保持明文
  if [[ "$compress" == "true" ]]; then
    gzip -f -- "$rotated"
  else
    mv -f -- "$rotated" "${dir}/${base}.1"
  fi
}
