# 故障排查

## Open WebUI 首次启动卡住/长时间无响应

### 现象

执行 `docker compose up -d` 后，Open WebUI 容器长时间处于 starting/重启状态，访问 8080 端口无响应。查看日志可以看到大量 HuggingFace 下载超时：

```bash
docker logs -f ollama-webui
```

输出类似：

```
Downloading sentence-transformers/all-MiniLM-L6-v2 from HuggingFace...
Timeout/CONNECT error to huggingface.co:443
```

### 根因

Open WebUI 内置了 **RAG（检索增强生成）** 功能，允许用户上传文档并通过语义搜索进行问答。

实现 RAG 需要**嵌入模型**将文本转换为向量。Open WebUI 默认使用本地嵌入方案，首次启动会自动从 HuggingFace 下载 `sentence-transformers/all-MiniLM-L6-v2` 模型（约 80MB，30 个文件）。

当服务器配置了代理（如 HTTP_PROXY）时，代理往往无法正常访问 HuggingFace S3 存储节点，导致下载极慢甚至失败，容器反复超时重启。

### 解决方案

在 `docker-compose.yml` 的 Open WebUI 容器中添加三个环境变量：

```yaml
environment:
  # 改用 Ollama 内置嵌入模型，不再从 HuggingFace 下载
  - RAG_EMBEDDING_ENGINE=ollama
  - RAG_EMBEDDING_MODEL=nomic-embed-text:latest
  # 禁止启动时联网下载任何模型
  - OFFLINE_MODE=true
  # 阻止代理劫持访问 HuggingFace（避免代理报错干扰）
  - NO_PROXY=127.0.0.1,localhost,ollama,open-webui,huggingface.co,*.huggingface.co
```

**各配置项说明：**

| 配置项 | 值 | 作用 |
|--------|-----|------|
| `RAG_EMBEDDING_ENGINE` | `ollama` | 切换到 Ollama 作为嵌入引擎，不再使用本地 sentence-transformers |
| `RAG_EMBEDDING_MODEL` | `nomic-embed-text:latest` | 指定 Ollama 中的嵌入模型 |
| `OFFLINE_MODE` | `true` | 完全禁止 Open WebUI 在启动时自动下载任何模型 |
| `NO_PROXY` | 含 huggingface.co | 确保对 HuggingFace 的请求不走代理，避免代理造成超时 |

### 部署嵌入模型到 Ollama

修改 docker-compose.yml 后，需要在 Ollama 中拉取嵌入模型：

```bash
docker exec ollama ollama pull nomic-embed-text:latest
```

该模型约 270MB，拉取完成即可正常使用。

### 效果

- Open WebUI 不再从 HuggingFace 下载任何文件，启动速度恢复正常（几十秒内启动完成）
- RAG 文档问答功能由 Ollama 的 `nomic-embed-text` 处理，功能等价
- 不再受代理访问 HuggingFace 缓慢的影响

---

## Account Activation Pending（账户待激活）

### 现象

访问 `http://<主机IP>:8080` 时，页面显示：

> Account Activation Pending
> Contact Admin for WebUI Access
> Your account status is currently pending activation.

即使 `WEBUI_AUTH=False` 已关闭认证，仍然出现此页面。

### 根因

数据库 `webui.db` 中用户表的 `role` 字段为 `pending`（待审批），而非 `admin` 或 `user`。即使 `WEBUI_AUTH=False`，Open WebUI 仍会检查用户角色状态，所有用户为 pending 时触发激活页面。

这通常发生在：
- 之前 `WEBUI_AUTH=True` 时注册了账号但未被管理员审批
- 将 `WEBUI_AUTH` 改为 `False` 后重建容器，但数据卷保留了旧用户状态

### 诊断

```bash
docker exec ollama-webui python3 -c "
import sqlite3
conn = sqlite3.connect('/app/backend/data/webui.db')
cur = conn.cursor()
cur.execute('SELECT id, name, email, role FROM user')
for r in cur.fetchall():
    print(f'  {r}')
conn.close()
"
```

如果看到所有用户 `role=pending`，则确认此问题。

### 解决方案

将所有 pending 用户提升为 admin：

```bash
docker exec ollama-webui python3 -c "
import sqlite3
conn = sqlite3.connect('/app/backend/data/webui.db')
cur = conn.cursor()
cur.execute(\"UPDATE user SET role='admin' WHERE role='pending'\")
conn.commit()
print(f'Updated {cur.rowcount} users to admin role')
conn.close()
"
```

操作完成后刷新页面即可正常访问，无需重启容器。

# Coding Agent 性能诊断与优化方案

## 硬件配置

| 组件 | 规格 |
|------|------|
| CPU | AMD EPYC 7302 16-Core (32 线程) @ 3.0GHz |
| GPU | 2 × NVIDIA GeForce RTX 4090 (24GB × 2, CUDA 8.9) |
| RAM | 125 GiB DDR4 |
| 磁盘 | 1.8TB NVMe SSD |
| GPU 拓扑 | 双卡通过 PCIe 连接 (NODE)，非 NVLink |

## 当前运行状态

```
Ollama 0.32.4 正在运行 (docker-compose: /root/deAI/infra/ollama/):
  模型: qwen3-coder-opt:30b (Q4_K_M 量化, ~18GB 磁盘, Modelfile 固定 32K ctx)
  上下文: 32768 tokens (Modelfile PARAMETER num_ctx)
  GPU 0: ~12.0 GB / 24 GB
  GPU 1: ~11.5 GB / 24 GB (双卡均衡分布)
  Flash Attention: 已启用 (OLLAMA_FLASH_ATTENTION=1)
  KV Cache: q8_0 量化 (OLLAMA_KV_CACHE_TYPE=q8_0)
  实测速度: ~153 t/s (32K 上下文)
```

### 模型存储位置

```bash
# 模型存在 Docker Volume 中
docker volume inspect coding-agent_coding_agent_ollama_data
# → 宿主机路径: /var/lib/docker/volumes/coding-agent_coding_agent_ollama_data/_data

# 查看已下载模型
docker exec coding-agent-ollama ollama list

# 查看模型文件实际占用
du -sh /var/lib/docker/volumes/coding-agent_coding_agent_ollama_data/_data/
# → 约 18GB

# 模型文件结构
ls /var/lib/docker/volumes/coding-agent_coding_agent_ollama_data/_data/models/
# → blobs/  manifests/
```

模型不存放在宿主机文件系统，而是由 Docker Volume 管理。即使删除容器重建，只要 volume 不删，模型就不会丢失。

## 核心瓶颈分析

### 瓶颈 1: 只用了 1 张 GPU，第二张完全闲置 (最严重)

双 4090 共 48GB 显存，当前只用了一张卡的 80%。这意味着：
- 推理计算能力浪费了 50%
- 总可用显存只利用了 40%
- 模型被迫跑在单卡上，batch size 和并发都受限

**原因**: Ollama 默认只把模型加载到一张 GPU 上。需要显式配置才能跨 GPU 分布。

### 瓶颈 2: 未启用 Flash Attention

Flash Attention 是注意力计算的标准优化，可以：
- 减少 30-50% 的 attention 计算时间和显存占用
- 显著降低首 token 延迟
- 对于长上下文场景提升尤为明显

**原因**: Ollama 默认不开启 Flash Attention，需要设置 `OLLAMA_FLASH_ATTENTION=1`。

### 瓶颈 3: KV Cache 使用 f16 精度

f16 KV Cache 精度过高，严重浪费显存：
- 30B 模型 @ 16K ctx, f16 KV Cache ≈ 4-5 GB
- 如果改用 q8_0 量化 KV Cache，相同显存可以支撑 32K+ 上下文
- 对生成质量的影响极小（KV cache 量化几乎无损）

**原因**: Ollama 默认 `OLLAMA_KV_CACHE_TYPE=f16`，需要手动改为 `q8_0`。

### 瓶颈 4: 模型是 MoE 架构，但未利用多卡并行

Qwen3-Coder-30B 是 MoE 模型（128 个专家，每次激活 8 个），MoE 天然适合多卡：
- 专家层可以分布到不同 GPU
- 双卡可以显著提升 MoE 推理速度
- 但 Ollama 对 MoE 多卡支持有限

## 2026-08-05 更新: 256K 默认上下文才是真正的性能杀手

### 问题发现

完成方案 A 的所有优化后（Flash Attention + KV 量化 + 双卡分布），线上实测发现网页响应仍然很慢，
生成速度只有 **44.7 t/s**。排查后发现根因：

> **qwen3-coder:30b 原生 Modelfile 未设置 `PARAMETER num_ctx`，模型使用默认最大上下文 262144 (256K)。**

```
$ docker exec ollama ollama ps
NAME               SIZE     PROCESSOR         CONTEXT
qwen3-coder:30b    48 GB    3%/97% CPU/GPU    262144   ← 256K!
```

### 原理分析

即使是短对话（例如 "写一个Python冒泡排序"），Ollama 也会为 256K 上下文
**预分配完整的 KV Cache**。MoE 30B 模型在双 4090 上的 KV Cache 开销：

| 上下文 | KV Cache 大小 (q8_0) | 单卡实际显存 | 生成速度 |
|--------|---------------------|-------------|---------|
| 256K | ~13 GB | 23.1 GB (接近打满) | **44.7 t/s** |
| 32K | ~1.6 GB | 12 GB | **153 t/s** |

256K 上下文的 KV Cache 吃掉了 13GB 显存，导致：
- 显存几乎打满，CUDA Graph / 算子优化空间被压缩
- Attention 计算需要扫描 256K 的 KV Cache，开销巨大
- 处理器显示 "3%/97% CPU/GPU"（部分层被迫回退到 CPU）

### 修复方案

通过 Modelfile 将默认上下文固定为 32K：

```
FROM qwen3-coder:30b
PARAMETER num_ctx 32768
```

创建为 `qwen3-coder-opt:30b`，权重共享（不占额外磁盘空间）。

**注意**: `OLLAMA_NUM_CTX` 环境变量 **不被 Ollama 识别**。
上下文必须在 Modelfile 中通过 `PARAMETER num_ctx` 设置，或在 API 调用时通过
`options.num_ctx` 动态指定。

### 修复后效果

| 指标 | 修复前 (256K) | 修复后 (32K) | 提升 |
|------|-------------|------------|------|
| 生成速度 | 44.7 t/s | 153 t/s | **3.4×** |
| 单卡显存 | 23.1 GB | 12 GB | 节省 48% |
| 处理器 | 3% CPU / 97% GPU | 100% GPU | 纯 GPU |
| 简单问答耗时 | 4.8s | 1.4s | **3.4×** |

### 如何临时使用长上下文

当确实需要 64K+ 长上下文时，在 API 调用中显式指定：

```bash
curl ... -d '{"model":"qwen3-coder-opt:30b","options":{"num_ctx":65536}}'
```

或在 Open WebUI 模型设置中调整 Context Length。此时速度会相应下降到 ~70 t/s，
属于正常的精度-速度权衡。

### 为什么同一会话中第一个问题慢、后续问题快

这是 Ollama 的 **Prompt Cache（KV Cache 前缀匹配）** 机制导致的。

**分析日志** (同一会话的连续两次请求):

```
=== 第一个问题 (task 2094)，新建会话 ===
new prompt, task.n_tokens = 6454
cached n_tokens = 1      ← 无缓存，逐块评估
cached n_tokens = 1758   ← 累计缓存建立中
cached n_tokens = 3805
cached n_tokens = 5852
prompt eval time = 784.74 ms / 6453 tokens    ← 6000+ token 全新评估: ~0.8s

=== 第二个问题 (task 2123)，同一会话 ===
selected slot by LCP similarity, sim_best = 0.981 (> 0.100 thold)
f_keep = 0.996           ← 保留 99.6% 的旧 KV Cache
cached n_tokens = 6453   ← 直接命中，只需评估 128 个新 token
prompt eval time =  48.10 ms /   128 tokens   ← 仅评估新增: ~0.05s
```

**工作原理**:

Open WebUI 的同一个会话中，每次请求都会把**全部历史消息**一起发送:

| 第N次请求 | Open WebUI 发送的 messages | 总 tokens | 需评估 |
|-----------|--------------------------|----------|--------|
| 第1次 | `[系统提示词, Q1]` | ~800 | **800 (全量)** |
| 第2次 | `[系统提示词, Q1, A1, Q2]` | ~1200 | **200 (仅新增)** |
| 第3次 | `[系统提示词, Q1, A1, Q2, A2, Q3]` | ~1600 | **200 (仅新增)** |

Ollama 通过 **LCP 最长公共前缀匹配**，发现第 N 次的 prompt 和第 N-1 次有 98% 以上重合，
直接复用已缓存的 KV Cache，只计算新增部分。

- **第一个问题**: prompt 评估 ~800ms
- **后续问题**: prompt 评估 ~50ms（**快 16 倍**）

这解释了为什么"同一会话第一个慢、后续快"——本质上后续问题只花了 5% 的时间在 prompt 处理上。

> 注意: 如果**新建一个会话**或**切换模型**，KV Cache 无法匹配，又会经历一次完整的 prompt 评估。

### 首次请求额外延迟

除了 prompt cache，还有两个因素也会让"第一个问题"感觉更慢：

1. **模型首次加载**（仅容器重启后）: 即使 `OLLAMA_KEEP_ALIVE=-1`，docker 重启后第一次请求需要从磁盘加载 18GB 权重到显存，额外耗时 3-5 秒
2. **Open WebUI 首次请求**：可能需要加载 WebUI 自身的一些上下文/模板，加上一层网络延迟

## 优化方案对比

### 方案 A: 原地修改 Ollama 配置 (低风险, 立即见效)

只修改 docker-compose.yml 中的 Ollama 环境变量，不换运行时。改动见 [变更对照表](#变更对照表)。

预期收益:
- 开启 Flash Attention → 推理速度提升 30-50%
- KV Cache q8_0 量化 → 显存释放 2-3GB, 可支撑 32K ctx
- 多卡分布 (`OLLAMA_SCHED_SPREAD=1`) → 利用第二张 GPU
- 上下文提升到 32K → 长代码理解能力翻倍

**风险**: 极低，只改配置不改架构。

**局限**: Ollama 的 MoE 多卡支持不够成熟，双卡利用率可能达不到理想状态。

### 方案 B: 迁移到 vLLM (高收益, 需要一次性迁移成本)

用 vLLM 替换 Ollama 作为推理后端。详见 [VLLM_MIGRATION.md](./VLLM_MIGRATION.md)。

### 方案 C: Ollama + vLLM 混合 (推荐过渡方案)

保留 Ollama 作为 fallback，新增 vLLM 作为主推理后端。
Open WebUI 支持同时连接多个后端。

## 推荐方案: 方案 A (立即) → 方案 B (2周内)

## 变更对照表

以下是 `/root/deAI/infra/llm/coding/docker-compose.yml` 相对 `/root/deAI/infra/coding-agent/docker-compose.yml` 的**全部变更**：

### Ollama 容器 — environment 变更

| 配置项 | 原值 | 新值 | 说明 |
|--------|------|------|------|
| `OLLAMA_NUM_CTX` | `"16384"` | **已删除** | 环境变量不被 Ollama 识别，上下文改由 Modelfile 控制 |
| `OLLAMA_FLASH_ATTENTION` | 未设置 | **`"1"`** | 新增: 启用 Flash Attention (↑30-50%) |
| `OLLAMA_KV_CACHE_TYPE` | 未设置 | **`"q8_0"`** | 新增: KV Cache 量化，节省 ~40% 显存 |
| `OLLAMA_SCHED_SPREAD` | 未设置 | **`"1"`** | 新增: 模型跨双 GPU 分布 |
| `OLLAMA_NUM_PARALLEL` | 未设置 | **`"2"`** | 新增: 允许 2 个并行请求 |
| `OLLAMA_MAX_LOADED_MODELS` | 未设置 | **`"2"`** | 新增: 允许加载 2 个模型 |

> ⚠️ **关键发现 (2026-08-05)**: `OLLAMA_NUM_CTX` 环境变量不被 Ollama 识别。
> 上下文固定必须通过 Modelfile 的 `PARAMETER num_ctx` 实现。
> 不使用 `qwen3-coder:30b` 直接请求，应使用 `qwen3-coder-opt:30b`（Modelfile 固定 32K）。

其余配置项（`OLLAMA_KEEP_ALIVE`, `OLLAMA_HOST`, 代理、DNS、volumes、deploy 等）**完全不变**。

### Open WebUI 容器 — 无变更

Open WebUI 部分与原版完全一致。

### Volume 名称

模型权重直接挂载宿主机路径 `/root/deAI/infra/ollama/data` → 容器内 `/root/.ollama`，
不再依赖 Docker Volume（原 `/root/deAI/infra/models` 已迁移至此）。
模型文件在宿主机直接可见，方便管理和备份。

## 部署步骤

### 1. 停掉旧服务

```bash
cd /root/deAI/infra/coding-agent
docker compose down
```

### 2. 启动优化版

```bash
cd /root/deAI/infra/llm/coding
docker compose up -d
```

> Volume 名称相同，已下载的 3 个模型（`qwen3-coder:30b`、`qwen3-coder-ctx16k:30b`、`qwen3-coder-ctx32k:30b`）无需重新拉取。

### 3. 创建优化模型 (固定 32K 上下文)

```bash
# Modelfile 固定默认上下文为 32K
cat << 'EOF' | docker exec -i ollama ollama create qwen3-coder-opt:30b -f -
FROM qwen3-coder:30b
PARAMETER num_ctx 32768
EOF
```

这基于已有模型创建新的引用（不占额外磁盘空间，仅 Modelfile 元数据不同）。

### 4. 验证

```bash
# 查看已加载模型（确认 CONTEXT 为 32768 而非 262144）
docker exec ollama ollama ps

# 查看所有模型
docker exec ollama ollama list

# 检查 GPU 使用（两张卡都应该有负载，每卡 ~12GB）
nvidia-smi

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
```

### 5. 访问页面

浏览器打开 `http://<主机IP>:8080`，在模型选择中切换到 `qwen3-coder-opt:30b`。

## 模型选择建议

| 场景 | 推荐模型 | 上下文 | 速度 |
|------|---------|--------|------|
| 日常编程对话 | `qwen3-coder-opt:30b` | 32K | ~153 t/s |
| 分析大文件/长代码 | `qwen3-coder-opt:30b` + `options.num_ctx=65536` | 64K | ~70 t/s |
| 最大长上下文 | `qwen3-coder-opt:30b` + `options.num_ctx=131072` | 128K | ~35 t/s |

> 不需要为每个上下文创建独立模型。`qwen3-coder-opt:30b` 固定基础 32K，
> 需要更长上下文时通过 API 参数或 Open WebUI 设置动态调整。

## 如何查看模型

```bash
# 查看所有已下载模型（容器内）
docker exec ollama ollama list

# 查看当前加载到显存的模型（重点关注 CONTEXT 列）
docker exec ollama ollama ps

# 查看某个模型的详细信息（参数量、量化方式、架构、Modelfile）
docker exec ollama ollama show qwen3-coder-opt:30b
docker exec ollama ollama show --modelfile qwen3-coder-opt:30b

# 查看模型文件在宿主机的实际路径
ls /root/deAI/infra/models/

# 查看模型占用磁盘空间
du -sh /root/deAI/infra/models/
```

## 显存预算分析

### 当前 (单卡 24GB, f16 KV Cache, 16K ctx)

| 组件 | 显存占用 |
|------|---------|
| 模型权重 (Q4_K_M) | ~18 GB |
| KV Cache (f16, 16K) | ~4 GB |
| 其他 (CUDA context 等) | ~1 GB |
| **合计** | **~23 GB** |
| 剩余 | ~1 GB |

→ 单卡几乎打满，第二张卡闲置。无法提升上下文。

### 优化后 (双卡 48GB, q8_0 KV Cache, 32K ctx)

| 组件 | 显存占用 |
|------|---------|
| 模型权重 (Q4_K_M, 双卡分布) | ~18 GB (9+9) |
| KV Cache (q8_0, 32K) | ~4 GB |
| 其他 | ~2 GB |
| **合计** | **~24 GB / 48 GB** |
| 剩余 | ~24 GB |

→ 双卡负载均衡，还有大量余量可以提升上下文或加载第二个模型。

### vLLM 方案 (双卡 48GB, AWQ 量化, 128K ctx)

| 组件 | 显存占用 |
|------|---------|
| 模型权重 (AWQ 4-bit, TP=2) | ~18 GB (9+9) |
| KV Cache (PagedAttention, 128K) | ~16 GB |
| 其他 | ~2 GB |
| **合计** | **~36 GB / 48 GB** |
| 剩余 | ~12 GB |

→ vLLM + AWQ 量化可以在双 4090 上跑 30B + 128K ctx。

## 回滚

如果优化后有问题，切回原版：

```bash
cd /root/deAI/infra/llm/coding
docker compose down

cd /root/deAI/infra/coding-agent
docker compose up -d
```

## 下一步

当需要更强性能时，参考 [VLLM_MIGRATION.md](./VLLM_MIGRATION.md) 迁移到 vLLM。
