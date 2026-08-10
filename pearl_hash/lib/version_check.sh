#!/usr/bin/env bash
set -euo pipefail

# -----------------------------------------------------------------------------
# 版本检测 / 自更新模块（基础能力）
#
# 支持的来源：
# - pearlhash/pearlhash-miner（legacy）
# - andru-kun/wildrig-multi（推荐用于 4090）
#
# 说明：
# - 本模块只提供“查询 latest release + 选择 asset + 下载/安装”的通用能力
# - 具体策略（例如运行中禁止更新、备份命名等）由入口脚本 pearl_hash 负责
# -----------------------------------------------------------------------------

# 复用 common.sh 里统一的目录解析函数，避免本文件再复制一份。
# 注意：此处 common.sh 尚未被 source，pearl_hash_script_dir 还未定义，
# 因此用"本文件所在目录"直接拼路径加载（等价于该函数对本模块返回的结果）。
source "$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/common.sh"

# pearl_hash__require_python3: 校验 python3 可用（版本解析/asset 选择依赖）
pearl_hash__require_python3() {
  pearl_hash_require_cmd python3
}

# pearl_hash_version__repo_for_source: 根据 UPDATE_SOURCE + MINER_FLAVOR 映射 GitHub 仓库
#  - github-pearlhash : 官方 legacy 仓库
#  - github-wildrig   : WildRig Multi 官方仓库
#  - auto             : 按 MINER_FLAVOR 自动选择
# 返回：仓库全名（如 andru-kun/wildrig-multi）；未知 source 返回 1
pearl_hash_version__repo_for_source() {
  local update_source="$1"
  local miner_flavor="$2"

  case "$update_source" in
  github-pearlhash) printf '%s' 'pearlhash/pearlhash-miner' ;;
  github-wildrig) printf '%s' 'andru-kun/wildrig-multi' ;;
  auto)
    if [[ "$miner_flavor" == "pearl" ]]; then
      printf '%s' 'pearlhash/pearlhash-miner'
    else
      printf '%s' 'andru-kun/wildrig-multi'
    fi
    ;;
  *)
    pearl_hash_err "未知 UPDATE_SOURCE：$update_source"
    return 1
    ;;
  esac
}

# pearl_hash_version_local_read_file: 从 bin/miner.version 读取本地版本标记
# 文件格式：首行 "flavor version"（如 "wildrig 0.49.6"）
# 返回：解析成功输出 "flavor version"；失败返回 1
pearl_hash_version_local_read_file() {
  local version_file="$1"
  [[ -f "$version_file" ]] || return 1

  local line
  line="$(head -n 1 -- "$version_file" 2>/dev/null || true)"
  line="$(pearl_hash_trim "$line")"
  [[ -n "$line" ]] || return 1

  local flavor ver
  read -r flavor ver <<<"$line"
  flavor="$(pearl_hash_trim "$flavor")"
  ver="$(pearl_hash_trim "$ver")"
  [[ -n "$flavor" && -n "$ver" ]] || return 1
  printf '%s %s' "$flavor" "$ver"
}

# pearl_hash_version_local_guess_from_binary: 通过执行 --version 猜测 miner 版本
# 作为 bin/miner.version 缺失时的回退方案（依赖 miner 支持 --version）。
pearl_hash_version_local_guess_from_binary() {
  local miner_bin="$1"
  [[ -x "$miner_bin" ]] || return 1

  local out
  out="$("$miner_bin" --version 2>&1 || true)"
  out="$(pearl_hash_trim "$out")"
  [[ -n "$out" ]] || return 1
  printf '%s' "$out"
}

# pearl_hash_version_remote_latest_tag: 直接从 GitHub releases 页面 HTML 提取最新 tag
# 不走 GitHub API（无需认证，不受限流），用 grep 匹配 releases/tag/ 提取版本号
pearl_hash_version_remote_latest_tag() {
  local repo="$1"
  local url="https://github.com/${repo}/releases"
  curl -sL --max-time 10 -H "User-Agent: pearl_hash/${VERSION:-unknown}" "$url" 2>/dev/null \
    | grep -oP 'releases/tag/[^"]+' \
    | head -n 1 \
    | sed 's|releases/tag/||'
}

# pearl_hash_version_remote_parse_tag_name: 从 tag 字符串输出版本号（兼容旧接口）
# 现在 tag 已经是纯版本号，直接透传
pearl_hash_version_remote_parse_tag_name() {
  local tag="$1"
  printf '%s' "$tag"
}

# pearl_hash_version_remote_pick_asset_url: 构建下载直链 URL
# wildrig: https://github.com/{repo}/releases/download/{tag}/wildrig-multi-linux-{tag}.tar.gz
# pearl:   https://github.com/{repo}/releases/download/{tag}/pearl-miner
pearl_hash_version_remote_pick_asset_url() {
  local tag="$1"
  local miner_flavor="$2"

  local repo="andru-kun/wildrig-multi"
  if [[ "$miner_flavor" == "pearl" ]]; then
    repo="pearlhash/pearlhash-miner"
    printf 'https://github.com/%s/releases/download/%s/pearl-miner' "$repo" "$tag"
  else
    printf 'https://github.com/%s/releases/download/%s/wildrig-multi-linux-%s.tar.gz' "$repo" "$tag" "$tag"
  fi
}

# pearl_hash_update_download_to: 下载文件到指定路径
# 带 3 次重试、1s 间隔，降低弱网下载失败概率
pearl_hash_update_download_to() {
  local url="$1"
  local out_file="$2"
  pearl_hash_require_cmd curl
  curl -fL --retry 3 --retry-delay 1 -H "User-Agent: pearl_hash/${VERSION:-unknown}" -o "$out_file" "$url"
}

# pearl_hash_update_install_wildrig_tarball: 解压 WildRig tar.gz 并安装其中可执行文件
# 流程：解压到临时目录 → 定位可执行文件 → install 安装到目标路径（0755）。
#      临时目录用 trap 自动清理。
# 兼容性说明：不同版本 tarball 内可执行文件名不同——
#   - 0.49.9 及以后：名为 wildrig-multi
#   - 更早版本     ：名为 wildrig
# 因此这里同时尝试两种名字，避免因文件名演进导致"找不到"失败。
pearl_hash_update_install_wildrig_tarball() {
  local tar_gz="$1"
  local dst_bin="$2"

  pearl_hash_require_cmd tar

  # 用全局变量 + trap 内 ${tmp_dir:-} 兜底，避免 local 变量在 set -u 下
  # 于函数 return 时被 trap 引用导致 unbound variable（与 cmd_update 同理）
  tmp_dir="$(mktemp -d)"
  trap 'rm -rf -- "${tmp_dir:-}"' RETURN

  tar -xzf "$tar_gz" -C "$tmp_dir"
  # 依次尝试多个候选文件名；优先带执行权限的（部分 tarball 内权限未设置则放宽）
  local candidates=("wildrig-multi" "wildrig")
  local found=""
  local cand
  for cand in "${candidates[@]}"; do
    found="$(find "$tmp_dir" -maxdepth 3 -type f -name "$cand" -perm -u+x 2>/dev/null | head -n 1 || true)"
    if [[ -n "$found" ]]; then
      break
    fi
    found="$(find "$tmp_dir" -maxdepth 3 -type f -name "$cand" 2>/dev/null | head -n 1 || true)"
    if [[ -n "$found" ]]; then
      break
    fi
  done
  [[ -n "$found" ]] || {
    pearl_hash_err "解压后未找到 wildrig/wildrig-multi 可执行文件（tarball: $tar_gz）"
    return 1
  }

  install -m 0755 -- "$found" "$dst_bin"
}

# pearl_hash_update_install_plain_binary: 直接安装普通二进制（pearl legacy）
pearl_hash_update_install_plain_binary() {
  local src_file="$1"
  local dst_bin="$2"
  install -m 0755 -- "$src_file" "$dst_bin"
}

# pearl_hash_version_write_local_file: 原子写入本地版本标记文件
# 先写临时文件再 mv，避免中途崩溃留下半截文件
pearl_hash_version_write_local_file() {
  local version_file="$1"
  local miner_flavor="$2"
  local version="$3"

  local tmp="${version_file}.tmp"
  printf '%s %s\n' "$miner_flavor" "$version" >"$tmp"
  mv -f -- "$tmp" "$version_file"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  pearl_hash_warn "version_check.sh 是模块文件，建议由入口脚本 source 后调用相关函数"
fi
