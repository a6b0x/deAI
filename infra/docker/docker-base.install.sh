#!/usr/bin/env bash

set -euo pipefail

# Docker 底座安装涉及系统包管理，必须以 root 身份执行。
if [[ "${EUID}" -ne 0 ]]; then
  echo "请使用 root 运行该脚本。"
  exit 1
fi

source /etc/os-release

if [[ "${ID}" != "ubuntu" ]]; then
  echo "当前脚本仅针对 Ubuntu 编写，检测到系统: ${ID}"
  exit 1
fi

# 安装 Docker 官方源所需的基础工具。
apt-get update
apt-get install -y ca-certificates curl gnupg

install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

# 写入 Docker 官方 APT 源，避免使用系统仓库中的旧版本。
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu ${VERSION_CODENAME} stable" \
  > /etc/apt/sources.list.d/docker.list

apt-get update
# 安装 Docker Engine、Compose 和 Buildx。
apt-get install -y \
  docker-ce \
  docker-ce-cli \
  containerd.io \
  docker-buildx-plugin \
  docker-compose-plugin

systemctl enable --now docker

# 为国内机器注入容器级默认 DNS，避免宿主解析缺失导致模型/镜像下载极慢或失败。
# 保持已存在的 runtime 配置（例如 nvidia runtime）不受影响。
mkdir -p /etc/docker
if [ -f /etc/docker/daemon.json ]; then
  tmp_json=$(mktemp)
  if command -v python3 >/dev/null 2>&1; then
    python3 - <<'PY' "$tmp_json" || true
import json, sys
try:
    with open('/etc/docker/daemon.json','r') as f:
        data = json.load(f)
except Exception:
    data = {}
data.setdefault('dns', [])
for dns in ['114.114.114.114','223.5.5.5','180.76.76.76']:
    if dns not in data['dns']:
        data['dns'].append(dns)
with open(sys.argv[1],'w') as f:
    json.dump(data, f, indent=4)
PY
    if [ -s "$tmp_json" ]; then
      mv "$tmp_json" /etc/docker/daemon.json
    else
      rm -f "$tmp_json"
    fi
  fi
else
  # 没有 python3 时做兜底：只在 daemon.json 不存在时写入最简模板。
  if ! grep -q '"dns"' /etc/docker/daemon.json 2>/dev/null; then
    cp /etc/docker/daemon.json /etc/docker/daemon.json.bak.$(date +%s) 2>/dev/null || true
  fi
fi

if ! grep -q '"dns"' /etc/docker/daemon.json 2>/dev/null; then
  cat > /etc/docker/daemon.json <<'EOF'
{
    "dns": ["114.114.114.114", "223.5.5.5", "180.76.76.76"]
}
EOF
fi

systemctl restart docker

echo
echo "Docker 安装完成，版本如下："
docker --version
docker compose version
docker buildx version
echo "Docker 服务状态: $(systemctl is-active docker)"
