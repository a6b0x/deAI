#!/usr/bin/env bash
set -euo pipefail

# -----------------------------------------------------------------------------
# common.sh —— 全项目共享的基础工具模块
#
# 该模块被入口脚本 pearl_hash 与 lib/*.sh 其余模块统一 source。
# 集中存放与业务无关的通用能力：路径解析、日志分级输出、字符串处理、
# 环境变量加载、CSV 解析、HTTP 请求等。
#
# 为什么单独抽出 _script_dir：入口脚本和每个 lib 模块都需要定位自身所在目录，
# 以便动态 source 兄弟模块（避免硬编码绝对路径）。统一收敛到本函数后，
# 其它模块只需一行 `source "$(pearl_hash_script_dir)/common.sh"` 即可复用，
# 消除各文件里重复的 5 份几乎相同的路径解析代码。
# -----------------------------------------------------------------------------

# pearl_hash_script_dir: 解析"调用本函数的外层脚本"所在目录的绝对路径
# 设计要点：
# - 本函数定义在 common.sh 中，会被入口脚本与各 lib 模块统一复用。
#   BASH_SOURCE[0] 永远指向 common.sh 自身，因此必须用 BASH_SOURCE[1]（调用方）
#   才能拿到"真正调用本函数的那份脚本"的路径：
#     * 入口脚本调用  → 返回入口脚本所在目录
#     * lib 模块 source 时调用 → 返回该模块所在目录（即 lib/）
# - while 循环：只要 $src 是符号链接 (-h) 就继续解析，最终得到真实文件路径
# - 相对链接（目标以 / 开头之外的相对路径）会基于链接所在目录拼成绝对路径
# - 最后输出脚本所在目录的绝对路径（供 source 兄弟模块、定位资源等使用）
pearl_hash_script_dir() {
  local src="${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}"
  while [[ -h "$src" ]]; do
    local dir
    dir="$(cd -P -- "$(dirname -- "$src")" && pwd)"
    src="$(readlink -- "$src")"
    [[ "$src" != /* ]] && src="${dir}/${src}"
  done
  cd -P -- "$(dirname -- "$src")" && pwd
}

# pearl_hash_ts: 生成当前时间戳（ISO-8601 秒级）
# 供日志、快照等统一使用，保证格式一致、便于脚本化解析
pearl_hash_ts() {
  date --iso-8601=seconds
}

# pearl_hash_log: 记录 INFO 级日志（输出到 stdout）
# 统一加时间戳前缀 [INFO]，便于与 warn/err 区分
pearl_hash_log() {
  printf '%s [INFO] %s\n' "$(pearl_hash_ts)" "$*"
}

# pearl_hash_warn: 记录 WARN 级告警（输出到 stderr）
# 用于"不影响主流程但值得注意"的情况（如磁盘偏低、温度偏高）
pearl_hash_warn() {
  printf '%s [WARN] %s\n' "$(pearl_hash_ts)" "$*" >&2
}

# pearl_hash_err: 记录 ERROR 级错误（输出到 stderr）
# 用于"可能导致操作失败"的情况，便于在管道/脚本中独立捕获
pearl_hash_err() {
  printf '%s [ERROR] %s\n' "$(pearl_hash_ts)" "$*" >&2
}

# pearl_hash_mask_middle: 对字符串做中间打码，只保留首尾若干字符
# 参数：
#   $1 原字符串（如钱包地址）
#   $2 保留前缀长度（默认 10）
#   $3 保留后缀长度（默认 6）
# 用途：config/status 打印钱包地址时脱敏，避免明文展示敏感信息。
# 若字符串本身很短（<= 前缀+后缀+3），直接原样输出（打码无意义）。
pearl_hash_mask_middle() {
  local s="$1"
  local keep_prefix="${2:-10}"
  local keep_suffix="${3:-6}"
  local n="${#s}"
  if (( n <= keep_prefix + keep_suffix + 3 )); then
    printf '%s' "$s"
    return 0
  fi
  printf '%s...%s' "${s:0:keep_prefix}" "${s:n-keep_suffix:keep_suffix}"
}

# pearl_hash_require_cmd: 校验指定命令是否可用
# 不可用时打印缺失提示并返回 1，供调用方决定是否中断
pearl_hash_require_cmd() {
  local cmd="$1"
  command -v "$cmd" >/dev/null 2>&1 || {
    pearl_hash_err "缺少依赖命令: $cmd"
    return 1
  }
}

# pearl_hash_mkdirp: 幂等创建目录（已存在则跳过）
pearl_hash_mkdirp() {
  local dir="$1"
  [[ -d "$dir" ]] || mkdir -p -- "$dir"
}

# pearl_hash_is_number: 判断字符串是否为合法数字（整数或小数）
# 用于对来自配置文件/参数的数字做前置校验，避免 awk/算术出错
pearl_hash_is_number() {
  [[ "${1:-}" =~ ^[0-9]+([.][0-9]+)?$ ]]
}

# pearl_hash_trim: 去除字符串首尾空白（空格、制表符、换行等）
# 用纯 bash 参数扩展实现，避免额外依赖 sed/awk，在循环中更高效
pearl_hash_trim() {
  local s="${1:-}"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

# pearl_hash_load_env_file_if_unset: 加载 .env 配置文件
# 加载优先级（从高到低）：环境变量 > .env > 脚本内默认值
# 关键保证：仅当"当前 shell 中该变量未设置"时才从 .env 赋值，
# 从而确保用户通过环境变量传入的值永远不被 .env 覆盖。
# 逐行解析：跳过空行/注释行，校验变量名合法性，过滤无 "=" 的行。
pearl_hash_load_env_file_if_unset() {
  local env_file="$1"
  [[ -f "$env_file" ]] || return 0

  local line
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="$(pearl_hash_trim "$line")"
    [[ -z "$line" ]] && continue          # 空行跳过
    [[ "$line" == \#* ]] && continue      # 注释行跳过
    [[ "$line" != *"="* ]] && continue    # 不含赋值符的行跳过

    local name="${line%%=*}"
    name="$(pearl_hash_trim "$name")"
    [[ -z "$name" ]] && continue
    # 仅接受合法的 shell 变量名，防止注入恶意变量名
    [[ "$name" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || continue

    # 只有未设置才赋值（保证环境变量优先级最高）
    if [[ -z "${!name+x}" ]]; then
      eval "$line"
    fi
  done <"$env_file"
}

# pearl_hash_parse_csv_ints: 校验逗号分隔的整型列表是否合法
# 用于 GPU_DEVICES 等"逗号分隔数字"配置的前置校验。
# 空串视为合法（表示不指定）；任一非纯数字项返回 1。
pearl_hash_parse_csv_ints() {
  local csv="${1:-}"
  csv="$(pearl_hash_trim "$csv")"
  [[ -z "$csv" ]] && return 0
  local out=()
  local IFS=,
  read -r -a out <<<"$csv"
  local i
  for i in "${out[@]}"; do
    i="$(pearl_hash_trim "$i")"
    [[ -z "$i" ]] && continue
    [[ "$i" =~ ^[0-9]+$ ]] || return 1
  done
  return 0
}

# pearl_hash_http_get: 发起 GET 请求并输出响应体
# 参数：
#   $1 URL
#   $2 超时秒数（默认 3）
# 使用 curl -f（失败即返回非 0）--max-time 限制超时，防止网络挂起阻塞脚本
pearl_hash_http_get() {
  local url="$1"
  local timeout_sec="${2:-3}"
  curl -fsS --max-time "$timeout_sec" -H "User-Agent: pearl_hash/${VERSION:-unknown}" "$url"
}

# pearl_hash_lookup_url: 拼接钱包查询直达链接
# 统一生成 pearlhash.xyz 钱包查询页地址，供 config/status 复用，避免重复拼接
pearl_hash_lookup_url() {
  local address="${1:-}"
  [[ -n "$address" ]] || return 1
  printf 'https://pearlhash.xyz/account/%s' "$address"
}

