
> 📌 记录本地 LLM 的选型决策：选哪个模型、用哪个推理引擎、权衡点是什么。

# Qwen

## ⚡ vLLM vs Ollama 选型 260816

🤔 双卡 GPU 服务器上同时装了 Ollama 和 vLLM，已有模型权重是否能在两套引擎间复用？在双 RTX 4090 的硬件条件下，哪个引擎能更充分地利用多卡算力？

---

✅ **结论**：双 GPU 服务器首选 vLLM，Ollama 留作备用或无 GPU 环境兼容方案。

| 对比项 | vLLM | Ollama |
|--------|------|--------|
| 多卡并行 | 原生 Tensor Parallel（TP=2），双卡显存与算力无缝融合 | 基于 llama.cpp 层拆分，跨卡效率低 |
| 显存管理 | PagedAttention，零碎片，长上下文多轮无需重算 | 粗放管理，长上下文（>32K）易 OOM |
| 权重格式 | **AWQ / GPTQ / FP8 / safetensors** | **GGUF**（llama.cpp 专用格式） |
| 工具调用 | 原生参数支持，结构化输出稳定 | 受 chat template 影响，部分模型易出错 |
| 适用硬件 | GPU 服务器 | CPU / Mac / 单卡消费设备 |

Ollama 的唯一优势是 `ollama run <模型名>` 一键启动，无需关心格式、挂载、量化参数。但在本机已有完整 docker-compose 和 download 脚本的情况下，这个优势已被抹平。

⚠️ **权重格式为何不能复用**：这不只是"文件格式不兼容"的问题，而是两套量化方案从根本上不同。

Ollama 使用 GGUF 格式（llama.cpp 私有格式），将模型权重、tokenizer、元数据全部打包进单个文件，量化方案是 Q4_K_M（llama.cpp 自研的 k-quant 算法）。vLLM 基于 HuggingFace transformers 生态，权重以 safetensors 分片存储，配套独立的 config.json 和 tokenizer 文件，量化方案是 AWQ（Activation-aware Weight Quantization）。

两者的本质差异在于量化算法不同，不是同一套数据换个容器打包：
- Q4_K_M：逐层对权重做均匀 4-bit 压缩，优化目标是 CPU / 单卡低内存推理
- AWQ：量化时保留对激活值影响最大的权重精度，推理质量更高，且能被 GPU Tensor Core 硬件加速

因此 vLLM 无法读取 GGUF，不是没有实现格式解析，而是不存在从 Q4_K_M 到 AWQ 的无损转换路径。必须从 ModelScope 重新下载 safetensors 格式的 AWQ 权重。

---

## 🔬 MoE 模型与稠密模型对比 260816

🤔 调研 Qwen3.8-27B 时发现它标注为"Dense"，而当前跑的 Qwen3-Coder-30B-A3B 是 MoE 架构——两者参数量级相近，推理时的计算量、显存占用、生成速度和推理质量上有哪些实质性差异？Qwen3.8-27B 在哪些场景上有质的提升，代价是什么？

---

MoE（Mixture of Experts）有 30B 参数存在显存中，但每处理一个 token，门控路由（Router）只挑选其中约 3B 的专家参数参与计算，其余待机。效果上相当于：用 30B 的"知识容量"做存储，用 3B 的计算量完成每次推理。

Dense 则没有路由选择，每个 token 必须经过全部 27B 参数的 64 层网络做完整矩阵运算，推理算力约为同等 MoE 的 9 倍。

| 对比项 | Qwen3‑Coder‑30B‑A3B（MoE，当前） | Qwen3.8‑27B（Dense） |
|--------|----------------------------------|---------------------|
| 总参数 | 30B | 27B |
| 每 token 激活参数 | **3B** | **27B**（100%） |
| 单 token 计算量 | 相当于 3B 模型 | 相当于 27B 模型（约 9 倍差距） |
| 生成速度 | ⚡ 极快 | 适中 |
| 推理深度上限 | 受限于 3B 激活量 | 更强 |
| 多模态 | ✗ 无 | ✓ 原生 Vision Tower（图文/视频） |
| 最大上下文 | 64K（vLLM 部署限制） | 256K 原生，可扩展至 1M |

🏗️ **Qwen3.8-27B 的架构亮点**：

**混合线性注意力（Hybrid Linear-Attention）**：64 层中 48 层 Gated DeltaNet 线性注意力 + 16 层标准 Gated Attention。标准 Attention 的 KV Cache 随序列长度平方增长，而线性注意力近似线性增长，这是在同等显存下能支持 256K 乃至 1M 上下文的关键。

**Multi-Token Prediction（MTP）**：内置 Draft Head，解码时单步可预测多个 token，有效弥补 Dense 模型相比 MoE 在生成速度上的劣势。

**Thinking 模式**：默认启用思维链（CoT），通过 `--reasoning-parser=qwen3` 开启推理解析；延迟敏感场景可在 prompt 中用 `reasoning_effort` 参数降低或关闭思考量。

🎯 **选型建议**：
- 选 **MoE**（当前 Coder-30B-A3B）：代码补全、高频工具调用、多用户并发，响应速度优先
- 选 **Dense**（Qwen3.8-27B）：深层逻辑推理、长文档分析、多模态图文理解、需要 Thinking 的复杂任务
