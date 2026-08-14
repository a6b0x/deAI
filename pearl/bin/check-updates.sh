#!/usr/bin/env bash
# check-updates.sh - 矿工镜像更新监控（forge / peakminer）
#
# 原理：对比「本地 RepoDigest」与「远程 registry digest」，
#       不同 = 有新版本。只在状态变化时通知/更新一次，避免每个 cron 周期重复告警。
#
# 用法：
#   ./check-updates.sh                  # 仅检查 + 通知（默认）
#   AUTO_UPDATE=1 ./check-updates.sh    # 发现新版自动 pull + up -d + prune
#
# 通知渠道（可叠加，均可选）：
#   TELEGRAM_BOT_TOKEN + TELEGRAM_CHAT_ID    -> Telegram 推送
#   NOTIFY_CMD="/path/to/hook.sh"            -> 自定义回调命令（可含 $MSG 占位）
#   都不设则仅写日志 logs/image-updates.log
#
# 状态文件：logs/.last-digests/<image>.digest  记录上次已处理版本，防止重复告警
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
LOG_DIR="$PROJECT_DIR/logs"
STATE_DIR="$LOG_DIR/.last-digests"
LOG_FILE="$LOG_DIR/image-updates.log"
AUTO_UPDATE="${AUTO_UPDATE:-0}"

mkdir -p "$STATE_DIR"

# 服务配置：镜像 | compose 服务名 | 容器名 | 展示名
SERVICES=(
  "hashraptor/forge|forgeminer|kryptex-prl-forgeminer|ForgeMiner"
  "peakminer/peakminer|peakminer|kryptex-prl-peakminer|PeakMiner"
)

log() {
  echo "[$(date '+%F %T')] $*" | tee -a "$LOG_FILE"
}

notify() {
  local msg="$1"
  log "$msg"
  if [[ -n "${TELEGRAM_BOT_TOKEN:-}" && -n "${TELEGRAM_CHAT_ID:-}" ]]; then
    curl -s --max-time 15 -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
      -d "chat_id=${TELEGRAM_CHAT_ID}" \
      -d "text=${msg}" >/dev/null 2>&1 \
      && log "Telegram 通知已发送" || log "Telegram 通知失败"
  fi
  if [[ -n "${NOTIFY_CMD:-}" ]]; then
    eval "MSG=\"$msg\" ${NOTIFY_CMD}" >/dev/null 2>&1 \
      && log "自定义回调已执行" || log "自定义回调失败"
  fi
}

# 本地 digest（运行中镜像 tag 实际指向的 digest）
local_digest() {
  docker inspect --format '{{index .RepoDigests 0}}' "$1:latest" 2>/dev/null \
    | sed 's/.*@//'
}

# 远程 digest：buildx imagetools（走 docker 凭据，无匿名 API 限流问题），
# 连续调用偶发失败，重试 3 次；仍失败则兜底用 Docker Hub API。
# 调试/演练：设 SIMULATE_REMOTE_DIGEST=sha256:xxxx 可强制"发现新版本"分支。
remote_digest() {
  [[ -n "${SIMULATE_REMOTE_DIGEST:-}" ]] && { echo "$SIMULATE_REMOTE_DIGEST"; return 0; }
  local d=""
  for _ in 1 2 3; do
    d=$(docker buildx imagetools inspect "$1:latest" --format '{{.Manifest.Digest}}' 2>/dev/null | tr -d '\r')
    [[ -n "$d" ]] && break
    sleep 2
  done
  if [[ -n "$d" ]]; then
    echo "$d"
    return 0
  fi
  # 兜底：Docker Hub API（匿名限流 100 req/6h，cron 每小时 2 次调用足够安全）
  curl -s --max-time 15 "https://hub.docker.com/v2/repositories/${1}/tags/latest" \
    | grep -o '"digest":"[^"]*"' | head -1 | cut -d'"' -f4
}

updated=0
for entry in "${SERVICES[@]}"; do
  IFS='|' read -r image svc container display <<< "$entry"
  name="${image##*/}"

  local_d=$(local_digest "$image")
  remote_d=$(remote_digest "$image")
  state_file="$STATE_DIR/$name.digest"
  last_seen="$(cat "$state_file" 2>/dev/null || echo "")"

  if [[ -z "$remote_d" ]]; then
    log "WARN $display: 无法获取远程 digest（网络/registry 问题），跳过"
    continue
  fi
  if [[ -z "$local_d" ]]; then
    log "WARN $display: 本地镜像 ${image}:latest 不存在，跳过"
    continue
  fi

  if [[ "$local_d" == "$remote_d" ]]; then
    log "OK   $display: 已是最新（$remote_d）"
    continue
  fi

  # 远程有新版
  short_l="${local_d:7:12}"; short_r="${remote_d:7:12}"
  msg="[矿工更新] $display 发现新版本: ${local_d:0:7} -> ${short_r}... (svc=$svc)"
  if [[ "$remote_d" == "$last_seen" ]]; then
    log "INFO $display: 新版 $remote_d 已通知/处理过，跳过重复告警"
    continue
  fi

  if [[ "$AUTO_UPDATE" == "1" ]]; then
    log "AUTO-UPDATE $display: 开始自动更新..."
    if (cd "$PROJECT_DIR" && docker compose pull "$svc" && docker compose up -d "$svc"); then
      notify "$msg
✅ 已自动更新并重启容器，等待验证..."
      docker image prune -f >/dev/null 2>&1 || true
      log "OK   $display: 自动更新完成，新 digest=$remote_d"
    else
      notify "$msg
❌ 自动更新失败，请手动处理: docker compose -f $PROJECT_DIR/docker-compose.yml up -d $svc"
    fi
  else
    notify "$msg
⚠️ 需手动更新: cd $PROJECT_DIR && docker compose pull $svc && docker compose up -d $svc"
  fi
  echo "$remote_d" > "$state_file"
  updated=1
done

# 心跳（便于确认 cron 正常工作）
[[ "$updated" == "0" ]] && log "心跳: 所有镜像最新，无需操作"
exit 0
