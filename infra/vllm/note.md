# vLLM 迁移笔记

> 记录 vLLM 迁移过程中的原始疑问、遇到的问题、原因分析与解决过程。
> 部署配置见 [docker-compose.yml](./docker-compose.yml)，下载脚本见 [download-model.sh](./download-model.sh)。

# 疑问：模型需要重新下载吗？

**时间**：2026-08-06

**我的疑问**：从 Ollama 迁移到 vLLM，之前已下载的模型能直接复用吗？

**结论**：需要重新下载。Ollama 的权重格式与 vLLM 完全不通用。

Ollama 的 GGUF（Q4_K_M）权重是 Ollama 专用格式，vLLM 无法直接读取，必须下载
ModelScope 的 AWQ 4-bit 量化权重。对比：

| 对比项 | Ollama 现状 | vLLM 需要 |
|--------|-------------|-----------|
| 存储位置 | `/root/deAI/infra/ollama/data/` | `/root/deAI/infra/vllm/data/` |
| 权重格式 | **GGUF**（`blobs/`+`manifests/`，Q4_K_M） | **safetensors**（AWQ 4-bit） |
| 模型标识 | `qwen3-coder-opt:30b` | `tclf90/Qwen3-Coder-30B-A3B-Instruct-AWQ` |
| 下载来源 | Ollama 仓库 | **ModelScope（魔搭）** |
| 磁盘占用 | 约 18GB | 约 16.8GB |

**踩过的坑**：`Qwen/Qwen3-Coder-30B-A3B-Instruct-AWQ` 这个 ID 在 HuggingFace 上**根本不存在**
（API 返回 401）！可用版本在 ModelScope 上：`tclf90/Qwen3-Coder-30B-A3B-Instruct-AWQ`
（AWQ 4-bit，16.8GB，支持 vLLM 0.9.2+，Qwen3MoeForCausalLM 架构）。

**权衡**：挂载目录隔离，与 Ollama 互不影响——Ollama 用 `/root/deAI/infra/ollama/data`，
vLLM 用 `/root/deAI/infra/vllm/data`。两个体积是不同格式不能复用。

---

# 疑问：镜像版本选哪个？

**时间**：2026-08-06

**我的疑问**：vLLM 镜像用 `latest` 还是锁一个明确的版本号？

**结论**：使用 `latest`（当前已拉取 vllm/vllm-openai:latest，ffb2d59b1c05）。

`vllm/vllm-openai` 官方预构建镜像，内置 OpenAI 兼容 API 服务，开箱即用。latest 支持
Qwen3 MoE + AWQ 量化 + Tensor Parallelism（TP=2），双卡并行通过 `--tensor-parallel-size 2`
启用，无需额外配置。

**风险权衡**：latest 会随上游滚动更新，重启可能拉到新版本引入不兼容。若日后需稳定，
可 `docker tag` 锁定当前版本，或出问题时降级到 `v0.17.0` 等明确版本。
Open WebUI 沿用 `ghcr.io/open-webui/open-webui:v0.10.2`，与 Ollama 一致，减少变量。

---

# 问题：镜像拉取慢且反复失败

**时间**：2026-08-06

**问题描述**：`docker pull vllm/vllm-openai` 下载 5.2GB 大 layer（`9dc141b872c1`）时极慢，
且报 `short read: unexpected EOF` 中断，`364.9MB/5.221GB` 又重新开始下载。

**原因分析**：
1. Docker daemon 配置了 7890 代理（`/etc/systemd/system/docker.service.d/http-proxy.conf`），
   所有 `docker pull` 走代理访问 Docker Hub，代理节点不稳定导致大文件中途 EOF
2. 免费镜像加速源（`docker.1ms.run` 等）实测带宽极低（<1KB/s）或直接 429 限流
3. 关于"重新开始"：Docker **支持 layer 级断点续传**，已完成的 layer 会保留
   （日志里大量 `Already exists`），只有校验失败的 `9dc141b872c1` 需要重下，属正常行为

**解决与改变**：在 `/etc/docker/daemon.json` 配置国内镜像加速源；实测筛选出可用源
`dockerproxy.net`（约 1.5MB/s，比之前快）；创建 [retry-pull.sh](./retry-pull.sh)
自动重试，配合断点续传最终拉取成功。

---

# 问题：下载模型时容器报 `unrecognized arguments`

**时间**：2026-08-06

**问题描述**：运行下载脚本时，容器报错：
```
vllm: error: unrecognized arguments: 3600 huggingface-cli download ...
```

**原因分析**：
1. 新版镜像入口变了：`vllm/vllm-openai:latest` 的 `ENTRYPOINT=[vllm serve]`，
   容器命令被当作 vllm 的参数
2. `huggingface-cli` 已弃用，新版需用 `hf` 命令

**解决与改变**：容器加 `--entrypoint ""` 覆盖 vllm 入口；`huggingface-cli download`
改为 `hf download`；环境变量 `HF_HUB_ENABLE_HF_TRANSFER` 改为新的 `HF_XET_HIGH_PERFORMANCE`。

---

# 问题：容器内无法访问 HuggingFace（超时/401）

**时间**：2026-08-06

**问题描述**：容器内 `hf download` 超时，访问 hf-mirror 或官方 HF 均失败，且模型返回 401。

**原因分析**：
1. 容器默认 **bridge 网络**无法直连 hf-mirror（超时）
2. 7890 代理只监听 `127.0.0.1`，容器内通过网关 IP 访问不到
3. **最根本**：`Qwen/Qwen3-Coder-30B-A3B-Instruct-AWQ` 这个模型 ID 在 HuggingFace 上不存在

**解决与改变**：给下载容器加 `--network host`，共享宿主网络（bridge 网络连不上外部）；
**彻底改用 ModelScope**——模型在国内 ModelScope 上存在（`tclf90/...AWQ`），直链下载实测
~35MB/s，无需代理、无需翻墙。

---

# 疑问：前端需要改吗？

**时间**：2026-08-06

**我的疑问**：从 Ollama 切到 vLLM，前端 Open WebUI 需要改吗？

**结论**：前端 UI 基本不改，但后端连接方式要改（后来发现并非简单改地址）。

vLLM 提供 OpenAI 兼容接口，Open WebUI 原生支持，前端页面不用动。但连接 vLLM 必须走
**OpenAI 协议**（`/v1/models`），不能走 Ollama 协议（`/api/tags`）。

**变化点**：
- 模型名变化：前端选 `qwen3-coder-opt:30b` → 改选 `qwen3-coder-30b`
- RAG 嵌入：当前 Open WebUI 用 Ollama 的 `nomic-embed-text`，vLLM 只做推理

---

# 问题：Open WebUI 显示"暂无可用模型"

**时间**：2026-08-06

**问题描述**：Open WebUI 能打开，但页面显示"暂无可用模型"。

**原因分析**：
1. 最初用 `OLLAMA_BASE_URL=http://127.0.0.1:18000/v1` 连接 vLLM，Open WebUI 走 **Ollama
   协议**（`/api/tags`、`/api/version`）查模型，vLLM 返回 404
2. 改为 `OPENAI_API_BASE_URL`（单数）后仍不行，因为数据库已有记录，环境变量不覆盖
3. **关键**：Open WebUI 配置数据库（`webui.db`）里 `openai.api_base_urls` 仍是默认的
   `https://api.openai.com/v1`，需直接改数据库

**解决与改变**：用 `OPENAI_API_BASE_URLS`（复数）环境变量，并**直接修改数据库**：
```
openai.api_base_urls = ["http://127.0.0.1:18000/v1"]  → 指向本机 vLLM
openai.api_keys = ["dummy"]
ollama.enable = false                                  → 禁用 Ollama 路由
```
改完重启 Open WebUI，模型列表正常显示 `qwen3-coder-30b`，对话成功。

---

# 问题：Open WebUI 显示"账号待激活"

**时间**：2026-08-06

**问题描述**：访问 Open WebUI 显示"账号待激活，请联系管理员"，即使 `WEBUI_AUTH=False`。

**原因分析**：数据库 `webui.db` 中用户表的 `role` 字段为 `pending`（待审批）。即使关闭
认证，Open WebUI 仍检查用户角色，所有用户 pending 时触发激活页面。

**解决与改变**：执行 SQL 将所有 pending 用户提升为 admin，刷新页面即可访问，无需重启：
```sql
UPDATE user SET role='admin' WHERE role='pending'   -- 6 个用户全部改为 admin
```

---

# 问题：工具调用报错（auto tool choice）

**时间**：2026-08-06

**问题描述**：在 Open WebUI 提问"现在是什么节气"时，返回错误：
```
"auto" tool choice requires --enable-auto-tool-choice and --tool-call-parser to be set
```

**原因分析**：Open WebUI 对话时会向 vLLM 发送 `tools`（工具调用）参数，但 vLLM 启动时
**未启用工具调用支持**，导致拒绝处理带工具的请求（返回 400）。

**解决与改变**：在 `docker-compose.yml` 的 vLLM command 里加两个参数，重建 vLLM 容器：
```
--enable-auto-tool-choice     # 启用自动工具选择
--tool-call-parser=qwen3_coder  # Qwen3-Coder 专用工具解析器
```
验证：模型能识别"查节气"需求并返回 `tool_calls`（调用 get_date），常规对话也正常。

**补充**：工具调用返回 `tool_calls` 后，Open WebUI 需要配置对应工具才能真正执行。
节气问答属于工具调用场景，模型本身不知道当前日期，需在 Open WebUI 工作区创建
"获取日期"工具并绑定到模型，才能正确回答节气。

---

# 部署记录

## 部署状态（2026-08-06）

| 项目 | 状态 | 说明 |
|------|------|------|
| 镜像拉取 | ✅ | vllm/vllm-openai:latest 已就绪 |
| 模型下载 | ✅ | ModelScope 16.8GB，17 文件校验通过（56115 张量） |
| 模型加载 | ✅ | vLLM 0.26.0，TP=2，双卡各占 ~9GB |
| 推理验证 | ✅ | 正常 |
| 生成速度 | ✅ | **~184 t/s**（超过 Ollama 153 t/s） |
| Open WebUI | ✅ | 模型列表正常，对话成功 |

## 待办

- [ ] RAG 嵌入决策：若完全下线 Ollama，需换 OpenAI 兼容嵌入源
- [ ] 浏览器实测：选择 `qwen3-coder-30b` 做真实对话

> 部署步骤（启动/停止/回滚/验证）等框架性内容已移至 [README.md](./README.md)。
> 本文件只记录疑问、问题与踩坑细节。

---

# 参考资料

- 迁移原理与显存预算: [`../ollama/VLLM_MIGRATION.md`](../ollama/VLLM_MIGRATION.md)
- 现有 Ollama 部署: [`../ollama/docker-compose.yml`](../ollama/docker-compose.yml)
