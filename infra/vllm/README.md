# vLLM 推理服务

基于 vLLM 的高性能 LLM 推理部署，双 RTX 4090，替代 Ollama 作为 Qwen3-Coder 的推理后端。

## 目录结构

```
vllm/
├── docker-compose.yml     # 服务编排（vLLM + Open WebUI）
├── download-model.sh      # 下载模型（ModelScope）
├── retry-pull.sh          # 自动重试拉取镜像
├── note.md                # 迁移过程的疑问与踩坑记录（细节）
├── data/                  # 模型权重（挂载到容器 /models）
└── README.md              # 本文档（框架/概览）
```

## 文件职责

| 文件 | 用途 | 何时使用 |
|------|------|---------|
| `docker-compose.yml` | 定义 vLLM 和 Open WebUI 两个服务 | 启动/停止/查看配置 |
| `download-model.sh` | 从 ModelScope 下载 AWQ 模型 | 首次部署 |
| `retry-pull.sh` | 反复重试 `docker pull` 直到成功 | 首次拉镜像（网络不稳） |
| `note.md` | 迁移疑问、问题、原因分析 | 排查问题时查阅 |
| `data/` | 模型权重目录 | 只读挂载，勿手改 |

## 架构

```
浏览器 ──► Open WebUI (:8080)
              │  OpenAI 协议 (/v1)
              ▼
          vLLM (:18000)
              │  TP=2 双卡并行
              ▼
      2 × RTX 4090 (48GB)
```

- **vLLM**：OpenAI 兼容推理服务，模型 `qwen3-coder-30b`（AWQ 4-bit，16.8GB）
- **Open WebUI**：前端，通过 OpenAI 协议连接 vLLM（非 Ollama 协议）
- **模型来源**：ModelScope `tclf90/Qwen3-Coder-30B-A3B-Instruct-AWQ`

## 与 Ollama 的关系

- **互斥切换**：vLLM 与 Ollama 不同时运行（共享 GPU/端口 8080）
- 两者模型格式不通用：Ollama 用 GGUF，vLLM 用 safetensors(AWQ)
- 回滚：切回 `/root/deAI/infra/ollama` 的 compose

## 快速开始

### 前置条件
- 已拉取镜像 `vllm/vllm-openai:latest`（如未拉取成功，运行 `bash retry-pull.sh`）
- 已下载模型（如未下载，运行 `bash download-model.sh`）

### 启动
```bash
cd /root/deAI/infra/vllm

# 首次部署前先停掉 Ollama（互斥）
cd /root/deAI/infra/ollama && docker compose down
cd /root/deAI/infra/vllm

# 启动
docker compose up -d

# 查看状态
docker compose ps
```

### 验证
```bash
# 检查模型列表
curl http://localhost:18000/v1/models

# 对话测试
curl http://localhost:18000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"qwen3-coder-30b","messages":[{"role":"user","content":"写一个 Python hello world"}],"max_tokens":100}'
```

### 停止 / 回滚
```bash
# 停止
cd /root/deAI/infra/vllm && docker compose down

# 回滚到 Ollama
cd /root/deAI/infra/ollama && docker compose up -d
```

## 关键配置速查

| 项 | 值 |
|----|-----|
| vLLM API 端口 | `18000`（容器内 8000） |
| Open WebUI 端口 | `8080` |
| 对外模型名 | `qwen3-coder-30b` |
| 模型并行 | TP=2（双卡） |
| 最大上下文 | 65536 |
| 模型挂载 | `./data` → `/models` |

## 常见问题

详细踩坑记录见 [note.md](./note.md)，包括：模型来源、镜像拉取、网络代理、
Open WebUI 模型列表、账号激活、工具调用等。
