# vLLM 引擎

## 🖥️ VS Code 右侧栏 Chat 接入本地 vLLM：配置与"首字慢"排查 260818

🤔 在 VS Code 右侧栏 Chat 面板接入本地 vLLM（`qwen3-coder-30b`，10.8.0.8:18000），配置后模型一直"正在思考"、首字响应很慢，到底该怎么配置、慢在哪？

---

✅ **结论**：VS Code 1.122+ **原生支持**自定义 OpenAI 兼容端点，无需任何插件。服务端实测极快（stream TTFB 0.005s、总耗时 0.24s、长 prompt 600KB 仅 9.5s、无 thinking），"还在思考"是 **VS Code 侧配置问题**。

**1. 图形化入口**：右侧栏 Chat 面板 → 聊天框上方模型选择器 → 齿轮图标 → 添加模型 → **自定义端点（Custom Endpoint）**，自动打开 `chatLanguageModels.json`。也可 `Ctrl+Shift+P` 搜 `Chat: Language Models`。

**2. 标准配置**（直接可用）：

```json
[
  {
    "name": "vLLM Local",
    "vendor": "customendpoint",
    "apiKey": "dummy",
    "apiType": "chat-completions",
    "models": [
      {
        "id": "qwen3-coder-30b",
        "name": "Qwen3-Coder-30B (Local)",
        "url": "http://10.8.0.8:18000/v1",
        "toolCalling": true,
        "vision": false,
        "maxInputTokens": 32768,
        "maxOutputTokens": 8192
      }
    ]
  }
]
```

`url` 只到 `/v1`（VS Code 自动拼 `/chat/completions`）；`apiKey` 任意占位（vLLM 不校验）。

**3. 三个必改的坑**：


| 坑               | 错误写法                           | 后果                                                                                                                         |
| ---------------- | ---------------------------------- | ---------------------------------------------------------------------------------------------------------------------------- |
| `vision`         | `true`                             | 模型是纯文本，VS Code 以为能看图会附加图像内容，交互异常卡住 → 必须`false`                                                  |
| `maxInputTokens` | `128000`                           | 超过 vLLM 的`--max-model-len=65536`，请求被拒/截断，表现为长时间无响应 → 设 ≤65536                                         |
| 冗余 provider    | 多留一个无`models` 数组的 provider | VS Code 自动探测出的模型 id 是 HF 原始名（`tclf90/...`），与 `served-model-name` 不一致，选错就空转 → 只留一个完整 provider |

**4. 服务端无"思考"验证法**：响应中无 `reasoning_content` 字段、无 `<think>` 标签 = vLLM 未启用 reasoning，模型不会自己"思考"。

**5. 长上下文首字慢是物理规律**：Agent 模式下 VS Code 每次请求把全部历史 + 工具结果 + 代码重发做 prefill。Qwen3-Coder-30B 实际激活 3B，prefill 约 3-6K token/s：上下文 2K → 首字 <1s；20K → 3-6s；50K+ → 10-15s+。缓解：新任务开新会话、按需引用文件、控制对话长度。

---

## ⚠️ forge占用 → vLLM 反复重启、WebUI 看不到模型 260818

🤔 网页端（Open WebUI）看不到模型，`docker ps` 显示 vllm 容器一直在重启，API 端口也连不上，是什么原因？

---

✅ **结论**：kryptex forge 容器占用 GPU 0（约 9GB 显存 + 利用率 100%），vLLM `--gpu-memory-utilization=0.90` 需要每卡 21.17 GiB，启动报错后由 `restart: unless-stopped` 无限重启循环 → `18000` 端口始终无服务 → WebUI 模型列表为空。

**启动失败关键报错**：

```
ValueError: Free memory on device cuda:0 (13.89/23.52 GiB) on startup is less than
desired GPU memory utilization (0.9, 21.17 GiB). Decrease GPU memory utilization...
```

**排查方法**：

```bash
nvidia-smi                          # 看谁占显存（forgeminer 进程 /opt/forge/forge）
docker inspect <容器> --format '{{.State.Restarting}} {{.RestartCount}}'   # 确认重启循环
docker logs vllm-coder 2>&1 | grep -iE "less than|free memory"            # 找根因报错
```

**解决**：停挖矿 → 显存释放 → 重启 vLLM 即可（`cd /root/deAI/infra/pearl && docker compose down`）。
⚠️ 关联上文 `gpu-memory-utilization 0.90→0.80` 条目：即使降到 0.80 也只给 forge 留 ~4.3GiB（forge 需 ~9.2GB），**挖矿与 vLLM 无法同卡共存，只能错开跑**。

---

## 📊 服务能力评估：并发上限与输出速率 260817

🤔 双 4090 + Qwen3-Coder-30B-A3B（AWQ, TP=2）当前服务到底能跑多少并发、输出速率多少？怎么判断是否够用、什么时候该调参？

---

✅ **结论**（归档时点实测，vLLM v0.26.0，模型 `qwen3-coder-30b`）：

**1. 最大并发 = 4**

- 硬性上限来自 `--max-num-seqs=4`（`infra/vllm/docker-compose.yml` `vllm-coder.command`），第 5 个请求进入等待队列。
- 理论值：启动日志里 vLLM 自报 `GPU KV cache size: 223,168 tokens`、`Maximum concurrency for 65,536 tokens per request: 3.41x`。
  - 算法：**KV cache 总容量 ÷ max-model-len** = 223,168 ÷ 65,536 ≈ 3.41
  - 即每个请求都用满 64K 上下文时，3 个并发已是极限；配置取 4 是因为实际请求上下文远小于 64K（日常聊天几十~几千 token）。
- KV cache 来源：每卡 24,564 MiB，`gpu-memory-utilization=0.80`，扣权重（AWQ 7.95 GiB/卡）+ CUDA graph 等后得 10.22 GiB/卡，双卡合计 223,168 tokens。

**2. 实测输出速率**（`/metrics` 直方图累计值推算，31 请求 / 2405 token）：

- 平均生成速度 ≈ **67 tokens/s**（单序列）：`inter_token_latency_seconds_sum 35.82 / count 2405`
- TTFT（首 token 延迟）≈ **113 ms**：`time_to_first_token_seconds_sum 3.49 / count 31`
- 注意：`docker logs` 里的 `Avg generation throughput`（每 10s 打印）是瞬时窗口值，随负载剧烈波动（0~15 tok/s），不代表硬件能力，评估能力看 `/metrics` 直方图。

**3. 实时监控命令**：

```bash
# 当前并发/排队/抢占/KV cache 用量
curl -s localhost:18000/metrics | grep -E "vllm:(num_requests_running|num_requests_waiting|num_preemptions_total|gpu_cache_usage_perc)"
# 一行算出平均生成速率
curl -s localhost:18000/metrics | \
  awk '/^vllm:inter_token_latency_seconds_(sum|count)/ {gsub(/\{.*/,""); if($0 ~ /_sum/) s=$2; else c=$2} END {printf "平均生成速度: %.1f tokens/s (共 %d 个 token)\n", c/s, c}'
```

**4. 判断并发是否够用的三指标**（归档时点全部健康：preemptions=0、waiting=0、KV cache 用量 0% → 4 并发远未吃满）：


| 指标                                      | 危险信号                                                       |
| ----------------------------------------- | -------------------------------------------------------------- |
| `num_preemptions_total`                   | >0 = 序列被挤出（并发/上下文过长），需降并发或降 max-model-len |
| `num_requests_waiting{reason="capacity"}` | 长期 >0 = 忙不过来，可加并发                                   |
| `gpu_cache_usage_perc`                    | 接近 1.0 再加大并发会触发抢占                                  |

**5. 扩容路径**（如需更大并发）：

- 短上下文场景（8~16K）直接把 `--max-num-seqs` 提到 6~8，观察 preemptions 不涨即可。
- 降 `--max-model-len` 到 32K：满并发理论值翻倍至 ~6.8。
- 提 KV cache：日志建议 `--kv-cache-memory=15249657856`（14.2 GiB/卡）可充分利用显存（当前 10.22 GiB/卡，+40% 容量）；前提是矿机容器（forge 绑 GPU0）已停，否则留不出空间。

---

## 🐛 download-model.sh：Content-Range 含 `\r` 导致大文件完整性校验失效 260817

🤔 `download-model.sh qwen38` 二次执行时，`model.safetensors`（18G）和 `model-mtp.safetensors`（811M）明明已经完整下载，却始终打印"已存在 (大小 18G)，跳过 (远端大小无法获取)"，而不是预期的"已存在且完整，跳过"。但 `get_remote_size` 函数里已经用 `awk` 做了 `gsub(/\r/,"",v)` 去除回车——为什么还会失效？

---

✅ **结论**：问题不在 `get_remote_size` 内部，而在调用侧。

`get_remote_size` 的 `awk` 只清理了 `Content-Range` 数值内的 `\r`，但 curl 的响应体本身是 HTTP/1.1 `\r\n` 格式——awk 处理后输出的字符串末尾仍可能带一个游离的 `\r`。传给 `remote_size` 变量后，`[ "${local_size}" -ge "${remote_size}" ]` 做整数比较时 bash 遇到 `849400424\r` 报错：

```
download-model.sh: line 158: [: 849400424\r: integer expression expected
```

bash 认为 `remote_size` 非整数，条件判断抛异常，进入 `[ -z "${remote_size}" ]` 分支，打印"远端大小无法获取"，实际上远端是能拿到的。

✅ **修复**：在赋值后加一次 `tr -d '\r'`：

```diff
- remote_size=$(get_remote_size "${file}")
+ # 去除 \r，避免 HuggingFace Content-Range 头含回车导致整数比较失败
+ remote_size=$(get_remote_size "${file}" | tr -d '\r')
```

修复后再次执行 `bash download-model.sh qwen38`，两个大文件正确输出"已存在且完整，跳过"，不再误判。

---

## 📥 Qwen3.8-27B（18G）通过代理断点续传下载完成 260817

HuggingFace `model.safetensors`（18.6 GB）下载过程中发生 **2 次连接中断**（`curl: (18) transfer closed with N bytes remaining`），curl `--retry 5` 自动断点续传重试，均恢复成功，最终完整下载。

- **第1次中断**：剩余约 16.6 GB 时断开，curl 丢弃 49MB 已缓冲数据后续传
- **第2次中断**：剩余约 14.5 GB 时断开，curl 丢弃 2.1GB 已缓冲数据后续传（速度提升到 500k-1MB/s 阶段，代理节点切换导致）
- **总耗时约 7-8 小时**（速度波动大：初期 6-100 KB/s，重试后高峰 1MB/s+）
- 脚本日志另有 `line 158: integer expression expected` 警告（即上条 `\r` bug）和 `line 188: tinue: command not found`（历史遗留，`continue` 在某次编辑中被行尾截断，已在当前版本自然修复）

最终两个模型均完整：


| 模型                             | 大小 | 来源        | 状态    |
| -------------------------------- | ---- | ----------- | ------- |
| Qwen3-Coder-30B-A3B-Instruct-AWQ | 16G  | ModelScope  | ✅ 完整 |
| Qwen3.8-27B-W4A16-AWQ            | 19G  | HuggingFace | ✅ 完整 |

---

## 📐 gpu-memory-utilization GPU 使用限制 260817

🤔 vLLM（TP=2，双 4090）与  forge（绑定 GPU 0）同机运行，vLLM 按 0.90 预留显存后 GPU 0 只剩 0.9GB，forge 启动分配显存失败（`CUDA driver error 2`）崩溃重启循环。调低 utilization 到多少既能给矿工留出空间、又不牺牲 vLLM 的 KV cache？

---

✅ **结论**：`0.90 → 0.80`，实测可用，KV cache 足够。

- **每卡 0.80 × 24GB ≈ 19.3GiB 占用**（实测 19727MiB/卡），释放约 2.5GiB/卡
- **硬占用构成**（不受 utilization 影响）：AWQ 权重 7.95 GiB + peak activation 0.37 + 非 torch 0.1 + CUDAGraph 0.11 ≈ 8.5 GiB/卡
- **KV cache：10.22 GiB/卡，共 223,168 tokens**（max_model_len=65536 场景下充足）
- 验证：`/v1/models` 返回 `qwen3-coder-30b`，`/health` 200，实测推理正常

参数变更位置：`infra/vllm/docker-compose.yml` `vllm-coder.command`。

⚠️ **两条关键经验**：

1. utilization 按每卡均分控制（TP=2 无法单独限制某张卡），降低后两卡对称释放，不影响 TP 负载均衡
2. 0.80 下 GPU 0 仍只剩 ~4.3GiB 空闲，**无法再容纳需 ~9.2GB 的 forge**——调参解决的是 vLLM 侧预留过大的问题，矿工与 vLLM 的容量冲突需另行分配 GPU（见后续条目）

---

## 🌐 Qwen3.8-27B AWQ 量化版国内无镜像，只能走代理 260816

🤔 `download-model.sh qwen38` 当前走 Clash 代理从 HuggingFace 下载，能否改走 ModelScope 国内源或 hf-mirror 镜像，避免代理流量？

---

✅ **结论**：不能。经过多轮搜索验证，目前只能走代理。

`philbert440/Qwen3.8-27B-W4A16-AWQ` 这个 AWQ 量化版**只存在于 HuggingFace**，ModelScope 上搜不到同款（官方 `Qwen/Qwen3.8-27B` 只有 BF16 原版，且 AWQ 量化版在 ModelScope 上不存在）。`hf-mirror.com` 对此模型直接 308 跳回 `huggingface.co`，等于没绕过。


| 方案                      | 可行性 | 原因                                                                                             |
| ------------------------- | ------ | ------------------------------------------------------------------------------------------------ |
| 走 Clash 代理（当前方案） | ✅     | `download-model.sh` 的 `download_from_huggingface` 函数通过 `curl -x http://127.0.0.1:7890` 下载 |
| ModelScope 国内源         | ❌     | 无此 AWQ 量化版                                                                                  |
| hf-mirror.com             | ❌     | 308 跳回 huggingface.co                                                                          |

**为什么必须用 AWQ 量化版？** 双 RTX 4090 总共 48GB 显存，BF16 原版 27B 模型权重 = 27B × 2 bytes = 54GB，已超过总显存，加上 KV Cache 等运行时开销完全无法运行。AWQ 量化压缩到 ~19.6GB，才能装下。

---

## 🔧 pull_policy: never 禁止 compose 自动拉取，统一由脚本管控 260816

🤔 `retry-pull.sh` 命名只强调"重试"机制，看不出在干什么；且 `docker compose up` 时如果镜像不存在会触发自带 `docker pull`，与脚本逻辑重复。

---

✅ **结论**：重命名脚本 + compose 加 `pull_policy: never`，三步职责清晰不重叠。

- `retry-pull.sh` → **`pull-engine.sh`**：明确这是拉取推理引擎镜像（与模型权重无关），与 `download-model.sh`（下载模型权重）命名对称
- [docker-compose.yml](../vllm/docker-compose.yml) 公共锚点 `x-vllm-common` 加 `pull_policy: never`，禁止 compose 自动拉取镜像，统一由 `pull-engine.sh` 负责
- 如果镜像不存在，`docker compose up` 会直接报错，提示用户先跑 `pull-engine.sh`，比之前静默触发一次大概率失败的内置 pull 更清晰

最终流程：

```
pull-engine.sh       ← 拉取推理引擎（vllm/vllm-openai:latest，~28GB，自动重试）
download-model.sh    ← 下载模型权重（safetensors，~17-20GB，断点续传）
docker compose up    ← pull_policy: never，只用本地已有镜像
```

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


| 对比项   | Ollama 现状                               | vLLM 需要                                 |
| -------- | ----------------------------------------- | ----------------------------------------- |
| 存储位置 | `/root/deAI/infra/ollama/data/`           | `/root/deAI/infra/vllm/data/`             |
| 权重格式 | **GGUF**（`blobs/`+`manifests/`，Q4_K_M） | **safetensors**（AWQ 4-bit）              |
| 模型标识 | `qwen3-coder-opt:30b`                     | `tclf90/Qwen3-Coder-30B-A3B-Instruct-AWQ` |
| 下载来源 | Ollama 仓库                               | **ModelScope（魔搭）**                    |
| 磁盘占用 | 约 18GB                                   | 约 16.8GB                                 |

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

---
