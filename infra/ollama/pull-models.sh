#!/usr/bin/env bash
# =============================================================================
# pull-models.sh — 下载模型到 /root/deAI/infra/ollama/data/（经 compose 挂载）
# =============================================================================
#
# 单独启动 Ollama → 下载模型 → 关闭 Ollama，全流程自包含。
#
# 后续加新模型: 在下方 PULL_MODELS 和 OPT_MODELS 数组中追加即可。
#
# 用法:
#   cd /root/deAI/infra/ollama && bash pull-models.sh
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="${SCRIPT_DIR}/docker-compose.yml"

OLLAMA_PORT="${OLLAMA_PORT:-11434}"
PULL_TIMEOUT="${PULL_TIMEOUT:-900}"

# ---- 需要拉取的模型（追加新模型只加这一行） ----
PULL_MODELS=(
  "qwen3-coder:30b"
  "nomic-embed-text:latest"
)

# ---- 需要基于已拉取模型构建的优化版（格式: "优化名:FROM模型:num_ctx"） ----
OPT_MODELS=(
  "qwen3-coder-opt:30b:qwen3-coder:30b:32768"
)

cleanup() {
  echo
  echo "==> 关闭 Ollama..."
  docker compose -f "${COMPOSE_FILE}" stop ollama
}
trap cleanup EXIT

# ---- 启动 Ollama ----
echo "==> 启动 Ollama..."
docker compose -f "${COMPOSE_FILE}" up -d ollama

echo "==> 等待 Ollama 就绪..."
until curl -fsS "http://127.0.0.1:${OLLAMA_PORT}/api/version" >/dev/null 2>&1; do
  sleep 2
done
echo "    Ollama 已就绪"

# ---- 拉取模型 ----
for model in "${PULL_MODELS[@]}"; do
  echo
  echo "==> 拉取: ${model}"
  timeout "${PULL_TIMEOUT}" docker exec ollama ollama pull "${model}"
done

# ---- 构建优化版模型 ----
for entry in "${OPT_MODELS[@]}"; do
  IFS=":" read -r opt_name from_model num_ctx <<< "${entry}"
  echo
  echo "==> 构建: ${opt_name} (FROM ${from_model}, num_ctx=${num_ctx})"
  docker exec ollama ollama create "${opt_name}" -f - <<EOF
FROM ${from_model}
PARAMETER num_ctx ${num_ctx}
EOF
done

# ---- 输出结果 ----
echo
echo "已安装模型:"
docker exec ollama ollama list
