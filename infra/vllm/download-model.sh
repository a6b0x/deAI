#!/usr/bin/env bash
# =============================================================================
# download-model.sh — 下载 vLLM 所需的 AWQ 量化模型权重
# =============================================================================
#
# 重要背景:
#   Qwen/Qwen3-Coder-30B-A3B-Instruct-AWQ 在 HuggingFace 上【不存在】(401)!
#   可用版本在 ModelScope(魔搭): tclf90/Qwen3-Coder-30B-A3B-Instruct-AWQ
#   - AWQ 4-bit, 约 16.8GB, 支持 vLLM(0.9.2+)
#   - 国内平台, 直链下载快(实测 ~12MB/s), 无需翻墙/代理
#
# 本脚本从 ModelScope 逐文件下载(支持断点续传 Range + 幂等跳过)。
#
# 用法:
#   cd /root/deAI/infra/vllm && bash download-model.sh
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
MODEL_DIR="${SCRIPT_DIR}/data/Qwen3-Coder-30B-A3B-Instruct-AWQ"

# ---- 模型仓库(追加新模型只改这几行) ----
MS_MODEL_ID="tclf90/Qwen3-Coder-30B-A3B-Instruct-AWQ"
MS_REVISION="master"

# 需要下载的文件列表(不含 . 开头的隐藏文件)
FILES=(
  "config.json"
  "configuration.json"
  "generation_config.json"
  "LICENSE"
  "merges.txt"
  "model-00001-of-00006.safetensors"
  "model-00002-of-00006.safetensors"
  "model-00003-of-00006.safetensors"
  "model-00004-of-00006.safetensors"
  "model-00005-of-00006.safetensors"
  "model-00006-of-00006.safetensors"
  "model.safetensors.index.json"
  "qwen3coder_tool_parser.py"
  "README.md"
  "tokenizer.json"
  "tokenizer_config.json"
  "vocab.json"
)

# ---- 下载超时(秒) ----
DOWNLOAD_TIMEOUT="${DOWNLOAD_TIMEOUT:-3600}"

echo "==> 目标模型: ${MS_MODEL_ID} (${MS_REVISION})"
echo "==> 下载目录: ${MODEL_DIR}"
mkdir -p "${MODEL_DIR}"
echo

# ---- 逐文件下载(断点续传 + 幂等跳过) ----
for file in "${FILES[@]}"; do
  url="https://modelscope.cn/api/v1/models/${MS_MODEL_ID}/repo?Revision=${MS_REVISION}&FilePath=${file}"
  dest="${MODEL_DIR}/${file}"

  echo "==> 下载: ${file}"

  # 已存在且非空则跳过
  if [ -f "${dest}" ] && [ -s "${dest}" ]; then
    echo "    已存在 (大小 $(du -h "${dest}" | cut -f1))，跳过"
    continue
  fi

  # 断点续传: -C - 从已有位置继续; 重试 3 次
  if ! timeout "${DOWNLOAD_TIMEOUT}" curl -C - -L --retry 3 --retry-delay 3 \
       -o "${dest}" "${url}"; then
    echo "    ✗ ${file} 下载失败"
    rm -f "${dest}"   # 移除不完整文件，避免下次误判已存在
    exit 1
  fi

  echo "    完成 (大小 $(du -h "${dest}" | cut -f1))"
done

# ---- 输出结果 ----
echo
echo "=== 下载完成 ==="
du -sh "${MODEL_DIR}"
echo
echo "=== 文件清单 ==="
ls -lh "${MODEL_DIR}"
