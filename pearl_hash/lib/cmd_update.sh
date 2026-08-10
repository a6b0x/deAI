#!/usr/bin/env bash
set -euo pipefail

# -----------------------------------------------------------------------------
# cmd_update.sh —— version / check-update / update 命令模块
# -----------------------------------------------------------------------------

source "$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/common.sh"

pearl_hash_cmd_check_update() {
  pearl_hash_ensure_dirs
  pearl_hash_load_config

  local repo
  repo="$(pearl_hash_version__repo_for_source "$UPDATE_SOURCE" "$MINER_FLAVOR")"
  local remote_tag
  remote_tag="$(pearl_hash_version_remote_latest_tag "$repo")"

  local local_ver=""
  local local_pair
  local_pair="$(pearl_hash_version_local_read_file "${BIN_DIR}/miner.version" 2>/dev/null || true)"
  if [[ -n "$local_pair" ]]; then
    local_ver="${local_pair#* }"
  fi

  echo "────────────────────────────────────────"
  echo "版本检查 (MINER_FLAVOR=${MINER_FLAVOR}, repo=${repo})"
  echo "────────────────────────────────────────"
  echo "本地 miner:   ${local_ver:-未知} (bin/miner.version)"
  echo "官方发布:     ${remote_tag:-未知}"
  echo "────────────────────────────────────────"
  if [[ -n "$remote_tag" && -n "$local_ver" && "$remote_tag" == "$local_ver" ]]; then
    echo "OK 已是最新版本"
  elif [[ -n "$remote_tag" ]]; then
    echo "WARN 存在新版本：${remote_tag}"
  else
    echo "WARN 未能获取远程版本（可能网络受限或 API 受限）"
  fi
}

pearl_hash_cmd_version() {
  pearl_hash_ensure_dirs
  pearl_hash_load_config

  echo "入口脚本版本: ${VERSION}"

  local local_pair
  local_pair="$(pearl_hash_version_local_read_file "${BIN_DIR}/miner.version" 2>/dev/null || true)"
  if [[ -n "$local_pair" ]]; then
    echo "本地 miner:   ${local_pair#* } (${local_pair%% *}) [bin/miner.version]"
  else
    local guess
    guess="$(pearl_hash_version_local_guess_from_binary "$(pearl_hash_miner_bin)" 2>/dev/null || true)"
    echo "本地 miner:   ${guess:-未知} [--version 回退]"
  fi

  pearl_hash_cmd_check_update || true
}

pearl_hash_cmd_update() {
  local yes="${1:-false}"
  pearl_hash_ensure_dirs
  pearl_hash_load_config

  pearl_hash_cleanup_stale_pid_file "$MINER_PID_FILE"
  local miner_pid
  miner_pid="$(pearl_hash_read_pid_file "$MINER_PID_FILE" 2>/dev/null || true)"
  if [[ -n "$miner_pid" ]] && pearl_hash_is_pid_running "$miner_pid"; then
    pearl_hash_err "矿工正在运行（pid=${miner_pid}）。为避免替换二进制导致异常，请先 ./pearl_hash stop"
    return 1
  fi

  if ! pearl_hash_confirm "确认下载并安装最新版本？" "$yes"; then
    pearl_hash_warn "已取消"
    return 1
  fi

  local repo
  repo="$(pearl_hash_version__repo_for_source "$UPDATE_SOURCE" "$MINER_FLAVOR")"
  local remote_tag
  remote_tag="$(pearl_hash_version_remote_latest_tag "$repo")"
  [[ -n "$remote_tag" ]] || {
    pearl_hash_err "未能获取远程最新版本号"
    return 1
  }

  local asset_url
  asset_url="$(pearl_hash_version_remote_pick_asset_url "$remote_tag" "$MINER_FLAVOR")"
  [[ -n "$asset_url" ]] || {
    pearl_hash_err "未能从 release assets 中选择下载文件（repo=${repo} flavor=${MINER_FLAVOR}）"
    return 1
  }

  tmp="$(mktemp -d)"
  trap 'rm -rf -- "${tmp:-}"' RETURN

  local download_file="${tmp}/asset"
  pearl_hash_log "下载：${asset_url}"
  pearl_hash_update_download_to "$asset_url" "$download_file"

  local dst_bin
  dst_bin="$(pearl_hash_miner_bin)"
  local bak=""
  if [[ -f "$dst_bin" ]]; then
    bak="${dst_bin}.bak.$(date +%Y%m%d%H%M%S)"
    mv -f -- "$dst_bin" "$bak"
  fi

  if [[ "$MINER_FLAVOR" == "wildrig" && "$asset_url" == *.tar.gz ]]; then
    pearl_hash_update_install_wildrig_tarball "$download_file" "$dst_bin"
  else
    pearl_hash_update_install_plain_binary "$download_file" "$dst_bin"
  fi

  pearl_hash_version_write_local_file "${BIN_DIR}/miner.version" "$MINER_FLAVOR" "$remote_tag"

  # 生成 help.txt：方便用户随时查阅矿工完整帮助，无需每次重新执行 --help
  if [[ -x "$dst_bin" ]]; then
    "$dst_bin" --help >"${BIN_DIR}/help.txt" 2>&1 || true
  fi

  pearl_hash_log "安装完成：${dst_bin}"
  [[ -n "$bak" ]] && pearl_hash_log "旧版本已备份：${bak}"
  pearl_hash_log "版本标记已写入：${BIN_DIR}/miner.version"
  pearl_hash_log "帮助文档已写入：${BIN_DIR}/help.txt"
}
