#!/usr/bin/env bash

set -euo pipefail

# 基于脚本自身位置定位 compose 和 env，避免监控目录调整后失效。
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="${SCRIPT_DIR}/docker-compose.yml"
ENV_FILE="${SCRIPT_DIR}/monitoring.env"

if [[ -f "${ENV_FILE}" ]]; then
  # 使用 set -a 让 source 进来的变量自动 export 为环境变量，确保 docker compose 能继承。
  set -a
  source "${ENV_FILE}"
  set +a
fi

# 启动监控栈后直接输出访问地址，便于快速确认页面入口。
# --force-recreate 确保端口等配置变更后容器被重建。
docker compose -f "${COMPOSE_FILE}" up -d --force-recreate

echo
echo "Prometheus 已启动: http://127.0.0.1:${PROMETHEUS_PORT:-9090}"
echo "Grafana 已启动: http://127.0.0.1:${GRAFANA_PORT:-3001}"
