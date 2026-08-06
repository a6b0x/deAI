# 部署与优化操作指南

## 变更说明

已从 `coding-agent` 独立部署，容器/数据卷均使用 `ollama` 前缀。相对原版的优化变更：

### Ollama 容器 environment 变更

| 操作 | 配置项 | 值 | 目的 |
|------|--------|-----|------|
| 新增 | `OLLAMA_FLASH_ATTENTION` | `1` | 启用 Flash Attention，推理加速 30-50% |
| 新增 | `OLLAMA_KV_CACHE_TYPE` | `q8_0` | KV Cache 量化，节省 2-3GB 显存 |
| 新增 | `OLLAMA_SCHED_SPREAD` | `1` | 模型跨双卡分布，利用第二张 4090 |
| 新增 | `OLLAMA_NUM_PARALLEL` | `2` | 允许 2 个请求并行处理 |
| 新增 | `OLLAMA_MAX_LOADED_MODELS` | `2` | 允许主模型+回退模型同时加载 |
| 删除 | `OLLAMA_NUM_CTX` | — | **该环境变量不被 Ollama 识别**，上下文只能通过 Modelfile 或 API 控制 |

### 关键发现：默认 256K 上下文是速度瓶颈 (2026-08-05)

原生 `qwen3-coder:30b` 自带 262144 (256K) 默认上下文。不使用 `options.num_ctx` 时，
Ollama 会分配巨大的 KV Cache（双卡各占 23GB），导致推理速度降到 **44.7 t/s**。

通过 Modelfile 将默认上下文固定为 32K 后，速度提升到 **153 t/s (3.4×)**：

| 上下文 | 单卡显存 | 生成速度 | 处理器 |
|--------|---------|---------|--------|
| 256K (原生) | 23.1 GB | 44.7 t/s | 3% CPU / 97% GPU |
| 32K (Modelfile) | 12 GB | **153 t/s** | **100% GPU** |

**解决方案**: 使用 `qwen3-coder-opt:30b`（Modelfile 固定 32K），不要直接用原名模型。

### Volume 变更

| 操作 | 说明 |
|------|------|
| 修改 | 从 Docker Volume 改为直接挂载宿主机目录 `/root/deAI/infra/ollama/data`（原 `/root/deAI/infra/models` 已迁移） |

其余配置（镜像版本、端口、DNS、Open WebUI）完全不变。

## 模型存储

```
宿主机路径: /root/deAI/infra/ollama/data/
├── models/
│   ├── blobs/          # 模型权重文件 (18.5GB)
│   └── manifests/      # 模型元数据 (几 KB)
```

```bash
# 查看已下载模型
docker exec ollama ollama list

# 查看模型文件大小
du -sh /root/deAI/infra/ollama/data/

# 查看当前加载到显存的模型（关注 CONTEXT 列）
docker exec ollama ollama ps
```

## 关于模型上下文

### 推荐方式：使用固定上下文的优化模型

`qwen3-coder-opt:30b` 通过 Modelfile 固定 32K 默认上下文，保证速度稳定在 150+ t/s。
权重与 `qwen3-coder:30b` 共享（不占额外磁盘）。

```bash
# 创建命令（已执行，仅记录）
cat << 'EOF' | docker exec -i ollama ollama create qwen3-coder-opt:30b -f -
FROM qwen3-coder:30b
PARAMETER num_ctx 32768
EOF
```

### 需要长上下文时：API 参数覆盖

不需要为每个上下文创建独立模型名。在 API 调用时通过 `options.num_ctx` 临时调整：

```bash
# 32K 上下文 (默认，最快的)
curl http://localhost:11434/api/generate -d '{
  "model": "qwen3-coder-opt:30b",
  "prompt": "...",
  "stream": false
}'

# 64K 上下文 (长代码分析)
curl http://localhost:11434/api/generate -d '{
  "model": "qwen3-coder-opt:30b",
  "prompt": "...",
  "options": {"num_ctx": 65536},
  "stream": false
}'
```

**Open WebUI 中**：在模型设置 → Advanced → Context Length 直接调滑块即可。

> ⚠️ **重要**: 不要直接用 `qwen3-coder:30b` 原名。它的默认上下文是 262144，
> 即使 Open WebUI 中设置了 Context Length 也会在第一次加载时先用 256K 初始化,
> 导致显存瞬间打满、速度极慢。

## 部署步骤

### 1. 启动服务

```bash
cd /root/deAI/infra/ollama
docker compose up -d
```

### 2. 创建优化模型

```bash
# 首次部署需要执行，后续不需要
cat << 'EOF' | docker exec -i ollama ollama create qwen3-coder-opt:30b -f -
FROM qwen3-coder:30b
PARAMETER num_ctx 32768
EOF
```

### 3. 验证

```bash
# 检查 GPU 使用（两张卡都应该有负载，每卡 ~12GB）
nvidia-smi

# 查看模型（确认 qwen3-coder-opt:30b 存在）
docker exec ollama ollama list

# 查看加载状态（确认 CONTEXT 为 32768 而非 262144）
docker exec ollama ollama ps

# 测试推理速度
time curl http://localhost:11434/api/generate -d '{
  "model": "qwen3-coder-opt:30b",
  "prompt": "解释 Rust 的所有权系统",
  "stream": false
}' | python3 -c "
import sys,json
r=json.load(sys.stdin)
tt=r['total_duration']/1e9
ec=r['eval_count']
print(f'{ec} tokens, {tt:.1f}s, {ec/tt:.1f} t/s')
"
# 期望: ~150 t/s

# 检查 WebUI
curl -s -o /dev/null -w "HTTP %{http_code}" http://localhost:8080/
```

### 4. 访问页面

浏览器打开 `http://<主机IP>:8080`，**选择 `qwen3-coder-opt:30b`**（不是原名）。

## 模型选择

| 场景 | 模型 | 上下文 | 速度 |
|------|------|--------|------|
| 日常编程对话 | `qwen3-coder-opt:30b` | 32K | ~153 t/s |
| 长代码/大文件分析 | `qwen3-coder-opt:30b` + num_ctx=65536 | 64K | ~70 t/s |
| 快速响应/备用 | `qwen3-coder:14b` | 16K | ~200 t/s |

> 同一个 `qwen3-coder-opt:30b`，不同场景只改 `num_ctx` 参数。
> 不需要创建 `-ctx16k`、`-ctx32k`、`-ctx64k` 等多个模型名。

## 重启服务

```bash
cd /root/deAI/infra/ollama
docker compose down && docker compose up -d
```

## 下一步

需要更强性能时参考 [VLLM_MIGRATION.md](./VLLM_MIGRATION.md)。

## 迁移记录

2026-08-05 从 coding-agent 独立部署，变更如下：

| 项目 | 旧值 | 新值 |
|------|------|------|
| Ollama 容器 | `coding-agent-ollama` | `ollama` |
| WebUI 容器 | `coding-agent-open-webui` | `ollama-webui` |
| WebUI 数据卷 | `coding_agent_openwebui_data` | `ollama_openwebui_data` |
| HF 缓存卷 | `coding_agent_webui_hf_cache` | `ollama_webui_hf_cache` |

旧容器和旧数据卷已清理。
