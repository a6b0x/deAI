# vLLM 推理服务

基于 vLLM 的高性能 LLM 推理部署，双 RTX 4090，替代 Ollama 作为推理后端。

通过 Docker Compose **profiles** 管理多个模型，同一时间只运行一个，按需切换。

## 可用模型

| Profile | 模型 | 类型 | 大小 | 来源 | 对外名 |
|---------|------|------|------|------|--------|
| `coder` | Qwen3-Coder-30B-A3B | MoE (30B/3B) | 16.8 GB | ModelScope | `qwen3-coder-30b` |
| `qwen38` | Qwen3.8-27B | 稠密 27B | 19.6 GB | HuggingFace | `qwen38-27b` |

## 目录结构

```
vllm/
├── docker-compose.yml     # 服务编排（vLLM × 2 profiles + Open WebUI）
├── download-model.sh      # 下载模型（支持 coder / qwen38）
├── pull-engine.sh         # 拉取 vLLM 推理引擎镜像（自动重试）
├── data/                  # 模型权重（挂载到容器 /models）
└── README.md              # 本文档
```

## 架构

```
浏览器 ──► Open WebUI (:8080)
              │  OpenAI 协议 (/v1)
              ▼
          vLLM (:18000)              ← profiles 决定加载哪个模型
              │  TP=2 双卡并行
              ▼
      2 × RTX 4090 (48GB)
```

- **vLLM**：OpenAI 兼容推理服务，通过 profiles 按需加载不同模型
- **Open WebUI**：前端，通过 OpenAI 协议连接 vLLM（非 Ollama 协议）
- 两个模型共用 18000 端口，同一时间只有一个在运行，切换后 WebUI 刷新即可

## 快速开始

### 前置条件

```bash
cd /root/deAI/infra/vllm

# 1. 拉取 vLLM 推理引擎镜像（大 layer 易中断，脚本自动重试断点续传）
bash pull-engine.sh

# 2. 下载模型权重（选其一）
bash download-model.sh coder    # Qwen3-Coder-30B (~16.8GB, ModelScope 国内源)
bash download-model.sh qwen38   # Qwen3.8-27B     (~19.6GB, HuggingFace 走代理)
```

> `docker-compose.yml` 已设置 `pull_policy: never`，compose 不会自动拉镜像，
> 必须先跑完 `pull-engine.sh` 再 `up`，两步职责明确不重复。

### 启动
```bash
cd /root/deAI/infra/vllm

# 首次部署前先停掉 Ollama（互斥）
cd /root/deAI/infra/ollama && docker compose down
cd /root/deAI/infra/vllm

# 启动 Coder 模型
docker compose --profile coder up -d

# 或启动 Qwen3.8 模型
docker compose --profile qwen38 up -d

# 查看状态
docker compose ps
```

### 切换模型
```bash
# 先停止当前模型
docker compose down

# 启动另一个模型
docker compose --profile qwen38 up -d    # 切换到 Qwen3.8
docker compose --profile coder  up -d    # 切回 Coder
```

两个模型共用 18000 端口不会冲突（同时只有一个在运行）。WebUI 始终指向 18000，切换后刷新页面即可看到新模型名。

### 验证
```bash
# 检查模型列表
curl http://localhost:18000/v1/models

# 对话测试（模型名根据当前 profile 变化）
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

## 与 Ollama 的关系

- **互斥切换**：vLLM 与 Ollama 不同时运行（共享 GPU/端口 8080）
- 两者模型格式不通用：Ollama 用 GGUF，vLLM 用 safetensors(AWQ)
- 回滚：切回 `/root/deAI/infra/ollama` 的 compose

## 关键配置速查

| 项 | 值 |
|----|-----|
| vLLM API 端口 | `18000`（容器内 8000） |
| Open WebUI 端口 | `8080` |
| 模型并行 | TP=2（双卡） |
| 模型挂载 | `./data` → `/models` |
| Coder 模型名 | `qwen3-coder-30b` |
| Qwen3.8 模型名 | `qwen38-27b` |

## 常见问题

详细踩坑记录见 [note-vllm.md](../docs/note-vllm.md)，包括：模型来源、镜像拉取、网络代理、
Open WebUI 模型列表、账号激活、工具调用、profiles 配置等。
