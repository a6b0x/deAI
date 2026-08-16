# vLLM 迁移笔记

> 📌 记录从 Ollama 迁移到 vLLM 的决策、踩坑与解决过程。部署配置见 [docker-compose.yml](../vllm/docker-compose.yml)，下载脚本见 [download-model.sh](../vllm/download-model.sh)。

---

## ⚙️ Compose profiles 单文件管理多模型、按需启动 260816

🤔 下载了两个模型权重（Qwen3-Coder-30B-A3B 和 Qwen3.8-27B），但双卡显存无法同时全力加载两个模型。能否在一个 docker-compose.yml 里同时声明两套模型配置，启动时按需选择其中一个，而不需要维护多个文件？

---

✅ **结论**：使用 Docker Compose 的 `profiles` 机制，原文件直接修改，不需要新建。两个模型各标一个 profile，`open-webui` 不加 profile 始终启动。

```yaml
services:
  vllm-coder:
    profiles: ["coder"]
    ports:
      - "18000:8000"
    command:
      - --model=/models/Qwen3-Coder-30B-A3B-Instruct-AWQ
      # ...

  vllm-qwen38:
    profiles: ["qwen38"]
    ports:
      - "18000:8000"    # 共用端口，同一时间只有一个在线，不冲突
    command:
      - --model=/models/Qwen3.8-27B-Instruct-AWQ
      # ...

  open-webui:
    # 不加 profile，任何 profile 启动时都会带上 WebUI
    environment:
      OPENAI_API_BASE_URLS: "http://127.0.0.1:18000/v1"
```

切换操作：

```bash
docker compose down                       # 先停止当前运行的模型
docker compose --profile qwen38 up -d    # 切换到稠密模型
docker compose --profile coder  up -d    # 切换回 Coder
```

两个服务共用 18000 端口不会冲突，因为同一时间只有一个在运行。WebUI 始终指向 18000，切换后刷新页面即可看到新模型名。

---

## 🔄 GGUF 与 AWQ 格式不通用，迁移需重新下载权重 260806

🤔 从 Ollama 切到 vLLM 时，磁盘上已经有 Ollama 下载好的 18GB GGUF 权重。两套引擎能不能共用同一份权重文件，避免重复下载占用磁盘空间？

---

✅ **结论**：需要重新下载。Ollama 的 GGUF 权重与 vLLM 的 AWQ safetensors 是两套完全不同的量化方案，不存在复用路径。

| 对比项 | Ollama 现状 | vLLM 需要 |
|--------|-------------|-----------|
| 存储位置 | `/root/deAI/infra/ollama/data/` | `/root/deAI/infra/vllm/data/` |
| 权重格式 | **GGUF**（`blobs/`+`manifests/`，Q4_K_M） | **safetensors**（AWQ 4-bit） |
| 模型标识 | `qwen3-coder-opt:30b` | `tclf90/Qwen3-Coder-30B-A3B-Instruct-AWQ` |
| 下载来源 | Ollama 仓库 | **ModelScope（魔搭）** |
| 磁盘占用 | 约 18GB | 约 16.8GB |

挂载目录相互隔离，两套引擎可以同时存在互不影响。

⚠️ **踩坑**：`Qwen/Qwen3-Coder-30B-A3B-Instruct-AWQ` 这个模型 ID 在 HuggingFace 上**根本不存在**（API 返回 401）。可用版本在 ModelScope：`tclf90/Qwen3-Coder-30B-A3B-Instruct-AWQ`（AWQ 4-bit，16.8GB，支持 vLLM 0.9.2+）。

---

## 🐳 使用 latest 镜像，稳定后锁定版本 260806

🤔 vLLM 官方镜像有 `latest` 和明确版本号（如 `v0.17.0`）两种选择。在双卡 4090 + Qwen3 MoE + AWQ 量化的环境下，用 `latest` 是否存在稳定性风险？

---

✅ **结论**：当前使用 `latest`（已拉取 `vllm/vllm-openai:latest`，digest `ffb2d59b1c05`），功能完整，后续有稳定性需求时再锁版本。

`vllm/vllm-openai` 官方预构建镜像，内置 OpenAI 兼容 API 服务，开箱即用。`latest` 已支持 Qwen3 MoE + AWQ 量化 + Tensor Parallelism（TP=2），双卡并行通过 `--tensor-parallel-size 2` 启用，无需额外配置。

⚠️ **风险**：`latest` 会随上游滚动更新，重启时可能拉到新版本引入不兼容。若日后需要稳定，执行 `docker tag vllm/vllm-openai:latest vllm/vllm-openai:v0.17.0` 锁定当前版本。Open WebUI 沿用 `ghcr.io/open-webui/open-webui:v0.10.2`，与 Ollama 版本一致，减少迁移变量。

---

## 🐢 镜像大 layer 拉取 EOF：代理不稳定，脚本自动重试解决 260806

🤔 `docker pull vllm/vllm-openai` 下载到 5.2GB 大 layer（`9dc141b872c1`）时极慢，且频繁报 `short read: unexpected EOF` 中断后又从头开始——下载是否真的在从头重来，还是有断点续传机制？

---

Docker **支持 layer 级断点续传**，已完成的 layer 会保留（日志里大量 `Already exists`），只有校验失败的 `9dc141b872c1` 需要重下，并非真正从头开始，属正常行为。

根本原因是网络问题：
1. Docker daemon 配置了 7890 代理（`/etc/systemd/system/docker.service.d/http-proxy.conf`），所有 `docker pull` 走代理访问 Docker Hub，代理节点不稳定导致大文件中途 EOF
2. 免费镜像加速源（`docker.1ms.run` 等）实测带宽极低（<1KB/s）或直接 429 限流

✅ **解决**：在 `/etc/docker/daemon.json` 配置国内镜像加速源，筛选出可用源 `dockerproxy.net`（约 1.5MB/s）；创建 [retry-pull.sh](../vllm/retry-pull.sh) 自动重试，配合断点续传最终拉取成功。

---

## ❌ 容器 ENTRYPOINT 变更导致下载命令无法执行 260806

🤔 按照文档用 vLLM 容器运行 `huggingface-cli download` 命令时，容器报 `vllm: error: unrecognized arguments`，命令根本没有执行，是哪里写错了？

---

原因有两个：
1. **镜像入口点变了**：新版 `vllm/vllm-openai:latest` 的 `ENTRYPOINT=[vllm serve]`，容器命令会被当作 `vllm serve` 的参数解析，而不是独立执行的 shell 命令
2. **CLI 命令已弃用**：`huggingface-cli` 已被新版废弃，需改用 `hf` 命令

✅ **解决**：容器启动时加 `--entrypoint ""` 覆盖 vllm 入口；`huggingface-cli download` 改为 `hf download`；环境变量 `HF_HUB_ENABLE_HF_TRANSFER` 改为新的 `HF_XET_HIGH_PERFORMANCE`。

---

## ❌ 容器网络隔离 + 模型 ID 不存在，改用 ModelScope 下载 260806

🤔 在容器内运行 `hf download` 时，访问 hf-mirror 和官方 HF 都失败——一个超时、一个 401。宿主机可以正常访问，容器内为什么连不上？

---

三个层叠的原因：
1. 容器默认 **bridge 网络**无法直连 hf-mirror（超时）
2. 7890 代理只监听 `127.0.0.1`，容器通过网关 IP 访问宿主机代理不通
3. **最根本**：`Qwen/Qwen3-Coder-30B-A3B-Instruct-AWQ` 这个模型 ID 在 HuggingFace 上根本不存在

✅ **解决**：给下载容器加 `--network host` 共享宿主网络；彻底改用 **ModelScope**——模型在国内 ModelScope 上存在（`tclf90/...AWQ`），直链下载实测 ~35MB/s，无需代理、无需翻墙。

---

## 🖥️ 切换 vLLM 后前端不动，连接协议从 Ollama 改为 OpenAI 260806

🤔 Ollama 和 vLLM 都能配合 Open WebUI 使用，切换后端引擎后，前端页面和配置要改多少？是简单改个地址，还是有更深的协议差异？

---

✅ **结论**：前端 UI 页面基本不改，但后端连接方式必须改，且不只是改地址那么简单。

vLLM 提供 OpenAI 兼容接口，Open WebUI 原生支持，前端页面不用动。但连接 vLLM **必须走 OpenAI 协议**（`/v1/models`），不能走 Ollama 协议（`/api/tags`）。

变化点：
- 模型名变化：前端选 `qwen3-coder-opt:30b` → 改选 `qwen3-coder-30b`
- RAG 嵌入：当前 Open WebUI 用 Ollama 的 `nomic-embed-text`，vLLM 只做推理，嵌入模型需单独处理

---

## ❌ Open WebUI 走 Ollama 协议导致模型列表为空 260806

🤔 vLLM 已经正常启动，API 也能响应，但 Open WebUI 页面一直显示"暂无可用模型"。检查日志看起来也没有明显报错，是哪个环节出了问题？

---

三个层叠原因：
1. 最初用 `OLLAMA_BASE_URL=http://127.0.0.1:18000/v1` 连接 vLLM，Open WebUI 走 **Ollama 协议**（`/api/tags`、`/api/version`）查模型，vLLM 返回 404
2. 改为 `OPENAI_API_BASE_URL`（单数）后仍不行，因为数据库已有记录，环境变量不覆盖已存在的配置
3. **关键**：Open WebUI 配置数据库（`webui.db`）里 `openai.api_base_urls` 仍是默认的 `https://api.openai.com/v1`，需直接修改数据库

✅ **解决**：用 `OPENAI_API_BASE_URLS`（复数）环境变量，并**直接修改数据库**：
```
openai.api_base_urls = ["http://127.0.0.1:18000/v1"]  → 指向本机 vLLM
openai.api_keys      = ["dummy"]
ollama.enable        = false                           → 禁用 Ollama 路由
```
改完重启 Open WebUI，模型列表正常显示 `qwen3-coder-30b`，对话成功。

---

## ❌ WEBUI_AUTH=False 不影响用户 role，账号激活需改数据库 260806

🤔 `WEBUI_AUTH=False` 已经设置关闭认证，但访问 Open WebUI 仍弹出"账号待激活，请联系管理员"。关闭认证应该不需要登录，为什么还有这个页面？

---

关闭认证（`WEBUI_AUTH=False`）只跳过登录流程，但 Open WebUI 仍然检查用户角色。数据库 `webui.db` 用户表中 `role` 字段为 `pending`（待审批），触发激活页面与认证开关无关。

✅ **解决**：执行 SQL 将所有 pending 用户提升为 admin，刷新页面即可访问，无需重启：
```sql
UPDATE user SET role='admin' WHERE role='pending'   -- 6 个用户全部改为 admin
```

---

## ❌ vLLM 未启用工具调用参数，对话时报 400 错误 260806

🤔 在 Open WebUI 中提问"现在是什么节气"时，返回报错而非正常回答。错误信息提到 `--enable-auto-tool-choice` 和 `--tool-call-parser`，但这是 vLLM 启动参数，为什么用户提问会触发这个？

---

Open WebUI 在对话时默认向 vLLM 发送 `tools`（工具调用）参数，但 vLLM 启动时**未声明支持工具调用**，导致拒绝处理带工具的请求（返回 400）。

```
"auto" tool choice requires --enable-auto-tool-choice and --tool-call-parser to be set
```

✅ **解决**：在 `docker-compose.yml` 的 vLLM command 里加两个参数，重建容器：
```
--enable-auto-tool-choice           # 启用自动工具选择
--tool-call-parser=qwen3_coder      # Qwen3-Coder 专用工具解析器
```

验证：模型能识别"查节气"需求并返回 `tool_calls`（调用 get_date），常规对话也正常。

⚠️ **补充**：工具调用返回 `tool_calls` 只是模型表达了"我需要调用工具"，Open WebUI 还需要在工作区创建对应工具（如"获取日期"）并绑定到模型，才能真正执行并返回结果。
