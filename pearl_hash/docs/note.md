# 资料参考

## 官方链接

| 资源 | URL |
|------|-----|
| Pearlhash 矿池官网 | `https://pearlhash.xyz/#start-mining` |
| WildRig Multi（官方推荐矿工） | `https://github.com/andru-kun/wildrig-multi` |
| pearl-miner（legacy，仅 H100/H200） | `https://github.com/pearlhash/pearlhash-miner` |

## 矿工选型速查

| 矿工 | 适用场景 | 最新版本 | 备注 |
|------|---------|---------|------|
| **WildRig Multi** | NVIDIA RTX 3000/4000/5000、AMD | 0.49.9（2025-08-07） | **官方推荐**，性能比 legacy 高约 20% |
| pearl-miner | NVIDIA H100 / H200 | V13（2026-08-05） | legacy，已停更，其他 GPU 不推荐 |

---

# 手动下载与测试（快速上手）

以下步骤完全手动操作，不需要任何自动化脚本，适合初次验证。

## 1. 下载 WildRig Multi（推荐）

```bash
# 进入工作目录
mkdir -p /root/deAI/pearl_hash/bin && cd /root/deAI/pearl_hash/bin

# 下载最新版（以 0.49.9 为例，可替换为实际最新版本号）
wget https://github.com/andru-kun/wildrig-multi/releases/download/0.49.9/wildrig-multi-linux-0.49.9.tar.gz

# 解压
tar -xzf wildrig-multi-linux-0.49.9.tar.gz

# 标记可执行
chmod +x wildrig

# 验证是否可运行
./wildrig --version
```

> 如果 `wget` 下载慢，可在浏览器打开 https://github.com/andru-kun/wildrig-multi/releases/latest ，手动下载 `wildrig-multi-linux-*.tar.gz` 后上传到服务器。

## 2. 下载 pearl-miner（备选，仅 H100/H200 场景）

```bash
cd /root/deAI/pearl_hash/bin

# 下载最新 legacy 版（V13）
wget https://github.com/pearlhash/pearlhash-miner/releases/download/V13/pearl-miner

# 标记可执行
chmod +x pearl-miner

# 验证
./pearl-miner --help
```

> **注意**：pearl-miner 已标记为 legacy 软件，仅推荐 NVIDIA H100/H200 使用。其他 GPU 请用 WildRig Multi。

## 3. 准备钱包地址

在 https://pearlhash.xyz/#start-mining 页面：
1. 选择矿池区域（EU/US 或 Asia）
2. 填入你的 Pearl (PRL) 钱包地址（以 `prl1` 开头）
3. 填写 Worker 名称（可选，默认用主机名）
4. 页面会自动生成启动命令

如果没有钱包地址，可以用以下测试地址（仅供测试，收益归该地址所有）：
```
prl1pldsjzegmcujgsp5rlhslp4gyg6zvkcqq2czmpqrptezay0pcmd8sveydvl
```

## 4. 手动启动测试（WildRig Multi）

用以下命令直接前台运行，观察输出是否正常：

```bash
cd /root/deAI/pearl_hash/bin

./wildrig \
  -a pearlhash \
  -o stratum+tcp://pool.pearlhash.xyz:9000 \
  -u prl1pldsjzegmcujgsp5rlhslp4gyg6zvkcqq2czmpqrptezay0pcmd8sveydvl \
  -w agent \
  -p x \
  --print-time 10
```

**预期输出**：启动后首先打印 banner，然后依次出现：

```
GPU #0: NVIDIA GeForce RTX 4090 [busID: xxx] [arch: sm89] [driver: 0]
kernel: 0, intensity: 8, cu: 128, mem: 24082Mb
GPU #1: NVIDIA GeForce RTX 4090 [busID: xxx] [arch: sm89] [driver: 0]
kernel: 0, intensity: 8, cu: 128, mem: 24082Mb
Start mining
use pool pool.pearlhash.xyz:9000 x.x.x.x
new job from pool.pearlhash.xyz:9000
```

看到 `new job from pool.pearlhash.xyz:9000` 即表示矿池连接成功、已开始接收任务。按 `Ctrl+C` 退出。

> 注：可能看到 `Failed to find OpenCL platform` 是正常的，NVIDIA 用 CUDA 后端不需要 OpenCL。`Authorization required` 是 headless 服务器的 X11 提示，可忽略。

## 5. 手动启动测试（pearl-miner 备选）

```bash
cd /root/deAI/pearl_hash/bin

./pearl-miner \
  --pool pool.pearlhash.xyz:9000 \
  --user 你的钱包地址 \
  --worker 你的矿工名
```

**预期输出**：启动后应出现类似：
```
Hashrate Total: 5.20e14 H/s
Hashrate GPU #0: 2.62e14 H/s
```

---

## 常用手动测试命令速查

| 目的 | 命令 |
|------|------|
| 验证 miner 二进制可执行 | `./wildrig --version` |
| 查看 WildRig 帮助 | `./wildrig --help` |
| 查看 pearlhash 算法参数 | `./wildrig -a pearlhash --help` |
| 前台运行（观察输出） | 见上面"手动启动测试" |
| 后台运行 + 写日志 | `nohup ./wildrig ... > /dev/null 2>&1 &` |
| 查进程 | `ps aux \| grep wildrig` |
| 终止挖矿 | `pkill wildrig` 或 `kill $(pgrep wildrig)` |
| 查看 GPU 状态 | `nvidia-smi` 或 `watch -n 1 nvidia-smi` |
| 矿池收益查询 | 浏览器打开 `https://pearlhash.xyz/account/你的钱包地址` |

---

## ⚠️ 重要：Rank-128 软分叉（2025-08-05 起）

**所有矿工必须更新到对应版本，否则大量 shares 被拒：**

- **WildRig Multi**：≥ 0.49.8（0.49.9 已包含该修复）
  - 区块 96251 之后，**必须移除 `--pearlhash-kernel` 参数**，否则大量 rejected
  - 预期算力下降约 5%
- **pearl-miner**：≥ V13
  - V13 是专为此次软分叉设计的最终版本

**验证方法**：启动后观察 rejected 比例，正常应 < 1%。若 rejected 持续 > 10%，说明版本或参数不对。

---

## WildRig Multi 关键命令选项速查

### 核心必填
| 参数 | 说明 | 示例 |
|------|------|------|
| `-a, --algo` | 算法名 | `-a pearlhash` |
| `-o, --url` | 矿池地址 | `-o stratum+tcp://pool.pearlhash.xyz:9000` |
| `-u, --user` | 钱包地址 | `-u prl1xxx...` |
| `-w, --worker` | 矿工名 | `-w my-rig-01` |
| `-p, --pass` | 矿池密码 | `-p x`（默认填 x） |

### 性能/运维常用
| 参数 | 说明 | 建议值 |
|------|------|--------|
| `--gpu-list` | 指定 GPU 编号 | `--gpu-list 0,1` |
| `--print-time` | 算力打印间隔（秒） | `--print-time 30` |
| `--api-port` | HTTP API 端口 | `--api-port 4058` |
| `--watchdog` | 内置看门狗 | 建议开启 |
| `--gpu-temp-limit` | 温度上限（°C） | `--gpu-temp-limit 85` |
| `--gpu-temp-resume` | 恢复挖矿温度（°C） | `--gpu-temp-resume 70` |
| `--gpu-intensity` | 单卡强度 | 4090 一般无需设置 |

### ⚠️ 已废弃参数
| 参数 | 原因 |
|------|------|
| `--pearlhash-kernel 1/2` | rank-128 软分叉后（区块 > 96251）必须移除，否则大量 rejected |

### Dev-Fee（开发抽成）
pearlhash 算法 devfee 约 **0.75%**（非高抽成算法列表，按默认档位计）。

### WildRig HTTP API 数据

`--api-port 4058` 后访问 `http://127.0.0.1:4058/` 返回 JSON，包含以下字段：

| 字段 | 说明 | 示例 |
|------|------|------|
| `hashrate.total[0]` | 10s 窗口总算力（H/s） | `591468022804966` |
| `hashrate.total[1]` | 60s 窗口总算力 | `0`（启动不足 60s） |
| `hashrate.total[2]` | 15min 窗口总算力 | `0`（启动不足 15min） |
| `hashrate.threads` | 每 GPU 线程算力数组 | `[[线程0, 线程1, ...], [GPU1...]]` |
| `hwmon.temp[]` | 每 GPU 温度（°C） | `[70, 75]` |
| `hwmon.fan[]` | 每 GPU 风扇转速（%） | `[51, 72]` |
| `hwmon.power[]` | 每 GPU 功耗（W） | `[450, 449]` |
| `hwmon.cclk[]` | 核心频率（MHz） | `[2430, 2385]` |
| `hwmon.mclk[]` | 显存频率（MHz） | `[10251, 10251]` |
| `results.shares_good` | 总 accepted 数 | `2` |
| `results.shares_accepted[]` | 每 GPU accepted 数 | `[1, 1]` |
| `results.shares_rejected[]` | 每 GPU rejected 数 | `[0, 0]` |
| `connection.pool` | 矿池地址 | `pool.pearlhash.xyz:9000` |
| `connection.ping` | 矿池延迟（ms） | `247` |
| `uptime` | 运行时长（秒） | `28` |

**脚本使用方式**：`status` / `metrics` / `stats.jsonl` 采样均优先读取此 API，用 awk 正则解析（不依赖 python3）。API 不可用时降级为解析日志。

---

## pearl-miner 命令速查（仅 H100/H200 场景）

```bash
./pearl-miner \
  --pool pool.pearlhash.xyz:9000 \
  --user 钱包地址 \
  --worker 矿工名
```

- 无 devfee（0% 矿工费）
- 无 API、无看门狗、无温度控制，所有运维依赖外层脚本

---

# 需求分析

## 配置管理
- 敏感信息不硬编码：脚本内无明文钱包地址、Token，全部外部化
- 配置集中管理：所有可调参数集中在单个文件，修改无需触及脚本
- 环境变量可覆盖：支持 `POOL_HOST=xxx ./pearl_hash start` 临时覆盖，优先级最高
- 配置可查询：提供 `config` 命令打印当前生效配置（敏感字段脱敏）

## 目录结构
- 按功能子目录组织：遵循项目约定，bin/ config/ logs/ run/ lib/ 分离
- 运行时文件动态创建：logs/ run/ 无需手动创建，脚本首次运行自动生成
- 唯一入口：仅保留一个可执行入口脚本，消除重复文件

## 进程管理
- 崩溃自动重启：进程异常退出（非手动 stop）时自动拉起，可配置最大重试次数
- 启动存活验证：启动后 30s 内验证三项：① 进程存活 ② 日志/API 出现算力摘要关键字 ③ 无致命错误关键词
- 优雅关闭流程：SIGTERM → 等待 10s → SIGKILL，超时强制终止
- 防并发启动：锁文件机制，禁止同时执行两个 start
- 进程暂停/恢复：提供 pause/resume（SIGSTOP/SIGCONT），无需真正退出即可释放算力

## 日志管理
- 多版本轮转归档：miner.log → .1 → .2.gz → ... → .7.gz，超量自动删除最旧
- 压缩归档：除当前日志外，历史文件全部 gzip 压缩
- 运行时轮转：不依赖重启，status 命令执行时 + 可配置 1h 定时检查
- 结构化统计日志：算力/提交数等关键指标额外写入 stats.jsonl，一行一 JSON，便于解析（若 miner 原生支持 HTTP API，优先读 API 仅做持久化备份）
- 会话标记：每次启动在日志写入明显分隔线，区分新旧会话

## GPU 资源协调
> 背景：本机除挖矿外还同时运行多个 Docker 镜像服务（infra/docker 目录下的监控、管理、其他 AI 服务等），以及按需启动的 LLM 大模型推理。GPU 是共享资源，需要在「挖矿收益」和「其他服务可用」之间做协调。
>
> 算法前提：Pearl 是纯算力型算法（非显存密集型，无 DAG 加载，显存占用极小），与其他 GPU 任务的冲突主要体现在 **CUDA 核心算力争抢** 和 **温度/功耗/风扇噪音**，而非显存 OOM。

- 启动前 GPU 可用性预检：对指定的每张卡，检查：① 设备存在 ② nvidia-smi 可访问 ③ 当前有其他 GPU 密集型进程时给出明确警告（不强制阻止，因为不涉及显存 OOM，由用户决策）
- LLM 前置辅助命令：pre_run_llm 命令一键暂停挖矿，LLM 结束后可 resume 恢复。即使不抢显存，LLM 和挖矿同时占用 CUDA 核心也会让 LLM 速度显著下降
- 其他镜像服务共存策略：监控栈（node_exporter / dcgm-exporter / cadvisor 等）仅占极少算力，默认允许共存不拦截；但检测到其他重度 GPU 容器时给出告警，并支持严格独占模式
- 温度与功耗监控告警：status 中显示 GPU 温度和单卡功耗，超过阈值标红告警；极端温度时拒绝启动或自动暂停（可通过 miner 原生 --temperature-limit 实现）

## 状态监控
- 进程基本信息：PID、运行时长、启动命令、内存占用
- 矿池连接状态：已连接/断开、最近一次连接成功/失败时间、是否登录成功
- 最近一次任务分配：Received new job 次数、loaded new job on gpu 状态
- 最近一次致命错误：从日志提取最近的 Error/FATAL 片段

## 可观测性
- 当前总算力：Hashrate Total 最新值（优先读 miner HTTP API）
- 单卡算力拆分：Hashrate GPU #0 / #1 / #N
- 比率统计：1h / 6h / 24h 平均算力（从 stats.jsonl 时间窗口聚合）
- 提交与拒绝：总 accepted / rejected 数量、拒绝率
- 单卡温度：每张卡的 temperature.gpu，超过 MAX_GPU_TEMP 标红
- 单卡功耗：power.draw 实时值，辅助判断整机功耗墙
- 显存占用：memory.used / memory.total（纯展示，不作为拦截条件）
- 风扇转速：fan.speed 百分比，异常情况告警
- GPU 利用率：utilization.gpu，辅助判断算力争抢
- 便捷日志查看：`logs [N=50]` 命令等价 tail -N，`logs -f` 等价 tail -f
- Prometheus 指标导出：`metrics` 命令输出标准 Prometheus 文本格式，可被 node_exporter textfile 直接采集；或直接暴露 miner 原生 API 端口
- 最近算力快速预览：`status --brief` 简化输出，适合脚本调用
- Web 查询链接：status 末尾输出 pearlhash.xyz/account/ 钱包地址查询直达链接

## 挖矿软件版本管理
- 版本标识：入口脚本、矿工程序都有明确可读取的版本号
- 远程版本检测：可一键查询官方最新 release 版本号（pearlhash legacy 仓库 + WildRig Multi 仓库，按 MINER_FLAVOR 自动选择）
- 版本对比提示：启动时若本地版本落后于官方最新，打印明显警告与下载跳转链接
- 可选自动更新：`update` 命令一键下载最新版本、备份旧版、验证可执行性后替换（默认需要手动确认，防意外）；WildRig tar.gz 解压也要考虑

## 鲁棒性
- 动态路径解析：全部使用 `SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)`，禁止硬编码绝对路径
- 原子 PID 写入：先写临时文件再 mv，防止竞态损坏 PID 文件
- 启动锁文件：防止两个 start 并发执行
- PID 僵尸清理：is_running() 中若 PID 文件存在但 kill -0 失败，自动 rm -f，避免假死
- 全局参数解析：支持 -y/--yes 危险操作跳过确认、--version 打印版本、--help 打印帮助
- set -euo pipefail：保留；grep 无匹配返回非 0 时用 || true 避免误杀
- 命令输入校验：start/stop/restart 等命令参数异常时给出清晰用法提示
- 错误分级输出：log / warn / err 三级输出，颜色区分，err 输出到 stderr

## 工程规范
- 版本标识：入口脚本顶部 VERSION 常量，--version 打印；矿工程序版本以文件标记 + -v/--version 输出优先
- 完整中文注释：所有函数、配置项、默认值加注释；关键分支说明「为什么这样做」
- 模块化拆分：logrotate / gpu_check / health_check / version_check 独立到 lib/ 目录，可单独 source 也可单独调试
- 配置样例：config/.env 所有参数都有中文注释与默认值
- 二进制可执行性检查：miner 二进制不存在或不可执行时自动 chmod +x 或报错
- nvidia-smi 可用性检查：无 nvidia-smi 给出明确驱动安装提示
- 矿池连通性前置检查：DNS 解析 + TCP 端口可达性，失败时打印 NETWORK_HINT 配置文案
- 磁盘空间预检：logs/ 所在分区剩余空间低于阈值（如 <500MB）时警告，防止日志写满磁盘

---

# 方案设计

## 规范目录结构
**对应需求**：目录结构类

```
/root/deAI/pearl_hash/
├── bin/
│   ├── wildrig-multi         # WildRig Multi 矿工二进制（官方推荐）
│   ├── pearl-miner            # 当 MINER_FLAVOR=pearl 时用（legacy 矿工，仅 H100/H200）
│   ├── miner.version          # 纯文本，记录当前二进制的版本号 + flavor
│   └── help.txt               # WildRig 完整帮助输出（参考用）
├── config/
│   └── .env                   # 独立配置文件（钱包、矿池、GPU、日志、MINER_FLAVOR...）
├── logs/                      # 日志目录（首次运行自动创建）
│   ├── miner.log
│   ├── stats.jsonl
│   ├── miner.log.1.gz
│   └── ...
├── run/                       # 运行时文件（首次运行自动创建）
│   ├── supervisor.pid         # supervisor 进程 PID
│   ├── miner.pid              # 矿工进程 PID
│   ├── .start.lock            # 并发启动锁
│   └── .manual_stop           # 手动停止标志
├── lib/
│   ├── common.sh              # 基础工具（日志、脱敏、路径解析、配置加载）
│   ├── supervisor.sh          # 后台守护进程（拉起矿工、启动验证、自动重启、定时采样）
│   ├── cmd_start.sh           # start 命令（预检 + flock + nohup 拉起 supervisor）
│   ├── cmd_stop.sh            # stop / pause / resume / pre_run_llm 命令
│   ├── cmd_status.sh          # status / config / logs 命令
│   ├── cmd_metrics.sh         # metrics 命令（Prometheus 格式）
│   ├── cmd_update.sh          # version / check-update / update 命令
│   ├── health_check.sh        # 健康检查 / 数据采样（API 优先 + 日志降级）
│   ├── gpu_check.sh           # GPU 预检
│   ├── logrotate.sh           # 日志轮转
│   └── version_check.sh       # 版本检测 / 自更新基础能力（pearl / wildrig 双源）
└── pearl_hash                 # 统一入口脚本（参数解析 + 命令分发，约 430 行）
```

关键实现：
- 入口脚本 mkdir -p 自动补齐目录，无需用户手动创建
- MINER_FLAVOR 决定 bin/ 下调用哪个可执行文件
- 所有命令逻辑拆分到 lib/cmd_*.sh，入口只做路由

---

## 配置与代码分离
**对应需求**：配置管理类 + 鲁棒性类 + 官方资料影响 + WildRig 切换准备

### config/.env 完整定义
```bash
# ============== 矿池配置 ==============
POOL_HOST="pool.pearlhash.xyz:9000"
# 可选矿池区域，仅用于展示/提示，实际连接以 POOL_HOST 为准
#  EU/US 默认: pool.pearlhash.xyz:9000
#  Asia     : 可在官网「Generate your launch command」选择 Asia 获取端点
POOL_REGION="EU/US"
# WildRig 需要加 stratum+tcp:// 前缀；若 MINER_FLAVOR=wildrig 则自动拼接
STRATUM_PREFIX_AUTO="true"
USER_ADDRESS="prl1pldsjzegmcujgsp5rlhslp4gyg6zvkcqq2czmpqrptezay0pcmd8sveydvl"
WORKER_NAME="$(hostname)"

# 网络解析失败时的提示文案（可配置，移除原脚本硬编码）
NETWORK_HINT="请确认 Clash 虚拟网卡/TUN 已开启，如刚打开建议等待几秒后重试。若仍失败可尝试切换 POOL_REGION 或直接 POOL_HOST 覆盖 Asia 端点。"

# ============== 矿工程序与版本（核心新增，支持 pearl/wildrig 双策略）==============
# 选择使用哪种矿工：pearl=官方 legacy pearl-miner；wildrig=官方更推荐 4090 的 WildRig Multi
MINER_FLAVOR="wildrig"
# 本地 miner 文件名（放在 bin/ 下）。不填时根据 MINER_FLAVOR 自动填 pearl-miner 或 wildrig-multi
MINER_BIN_NAME=""
# WildRig Multi 启动时的算法名（固定 pearlhash，无需修改）
WILDRIG_ALGO="pearlhash"
# WildRig 专属：每秒 stdout 打印摘要的间隔；0=使用 WildRig 默认
WILDRIG_PRINT_TIME="30"
# WildRig 专属：原生 API 端口（status / metrics 优先读这个，比 grep 日志稳）；0=关闭
WILDRIG_API_PORT="4058"
# WildRig 专属：是否开启内置 watchdog（与外层 bash watchdog 互补）
WILDRIG_WATCHDOG="true"
# 启动时是否自动检查更新（仅提示，不自动下载）
AUTO_VERSION_CHECK_ON_START="true"
# 自更新下载源：
#  - github-pearlhash    : 官方 legacy 仓库 pearlhash/pearlhash-miner/releases
#  - github-wildrig      : WildRig Multi 官方仓库 andru-kun/wildrig-multi/releases
#  - auto (默认)         : 根据 MINER_FLAVOR 自动选
UPDATE_SOURCE="auto"
# GitHub API 镜像/加速地址（国内环境可选，留空=直连 github.com）
GITHUB_API_BASE=""

# ============== GPU 资源控制 ==============
# 指定使用哪些 GPU（逗号分隔，留空=全部；WildRig 对应 --gpu-list）
GPU_DEVICES="0,1"
# 温度告警阈值（°C），status 中标红；若 MINER_FLAVOR=wildrig 则映射到 --gpu-temp-limit
MAX_GPU_TEMP="85"
# 是否严格独占 GPU：true=检测到其他 compute 进程就拒绝启动；false=仅打印警告
# 注意：DCGM/Prometheus 监控容器、Xorg 等轻量进程默认忽略；仅针对重度 compute 进程判定
GPU_STRICT_EXCLUSIVE="false"
# 严格独占模式下忽略的进程名（以逗号分隔，支持通配匹配）
GPU_IGNORE_PROCS="dcgm-exporter,nvidia-cuda-mps-control,Xorg"

# ============== 日志控制 ==============
LOG_MAX_SIZE_MB="50"          # 当前日志超过此大小触发轮转
LOG_ROTATE_KEEP="7"           # 保留归档份数
LOG_COMPRESS="true"           # 归档是否 gzip 压缩
LOG_STATS_JSONL="true"        # 是否同步写入结构化 stats.jsonl（即使有 API 也保留一份磁盘备份）
LOG_RUNTIME_CHECK_INTERVAL="3600"  # 运行时轮转检查间隔（秒），0=关闭

# ============== 进程守护 ==============
AUTO_RESTART="true"           # 崩溃后是否自动重启（若 WildRig 已开 --watchdog，也保留外层双保险）
AUTO_RESTART_MAX_RETRIES="5"  # 最大连续重启次数，超限放弃（防启动循环）
AUTO_RESTART_DELAY_SEC="5"    # 每次重启前等待秒数
STARTUP_VERIFY_TIMEOUT_SEC="30"  # 启动验证最长等待时间
# 启动成功关键字：若 MINER_FLAVOR=wildrig 有 API，优先用 API /health 判定；否则从日志 grep 关键字
STARTUP_VERIFY_KEYWORD_WILDRIG="speed"    # WildRig 典型摘要行含 speed / hashrate 等关键词
STARTUP_VERIFY_KEYWORD_PEARL="Hashrate Total"  # legacy pearl-miner 典型
STARTUP_FAIL_KEYWORDS=("Connection refused" "Error" "FATAL")  # 任一出现即失败

# ============== 矿池连通性检查 ==============
POOL_DNS_CHECK="true"         # 是否检查 DNS 解析
POOL_TCP_CHECK="true"         # 是否做 TCP 端口预检查
POOL_TCP_TIMEOUT_SEC="5"      # TCP 检查超时

# ============== 磁盘与依赖预检 ==============
MIN_DISK_SPACE_MB="500"       # logs/ 所在分区剩余空间低于此值打印警告
```

### 加载优先级（从高到低）
环境变量 > config/.env > 脚本内默认值（fallback）

关键实现伪代码：
```bash
# 入口脚本开头
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/config/.env"

# 1. 先设置脚本内默认值（fallback）
POOL_HOST="${POOL_HOST:-pool.pearlhash.xyz:9000}"
MINER_FLAVOR="${MINER_FLAVOR:-wildrig}"
# ... 所有默认值 ...

# 2. 再加载 .env，对每一项判断「只有 shell 中不存在才赋值」，确保环境变量优先级更高
```

### config 命令输出示例
```
$ ./pearl_hash config
────────────────────────────────────────
pearl_hash 当前生效配置
────────────────────────────────────────
矿池地址:     pool.pearlhash.xyz:9000 (EU/US)
钱包地址:     prl1pldsjze...sveydvl  (脱敏)
工作者名称:   agent260721
查询页面:     https://pearlhash.xyz/account/prl1pldsjze...
────────────────────────────────────────
矿工类型:     WildRig Multi (官方推荐 4090)
  算法:       pearlhash
  kernel:     2
  API port:   4058
本地版本:     0.49.6 (bin/miner.version)
官方最新:     0.49.6 (已最新)
────────────────────────────────────────
使用 GPU:     0, 1
温度上限:     85 °C (映射到 WildRig --temperature-limit)
GPU 独占:     关闭 (检测到其他重算力进程仅警告)
────────────────────────────────────────
日志限制:     50 MB × 7 份 (gzip)
自动重启:     开启 (最多 5 次, 间隔 5s)
────────────────────────────────────────
配置文件:     /root/deAI/pearl_hash/config/.env
覆盖方式:     POOL_HOST=xxx ./pearl_hash start
```

---

## 进程守护与高可用
**对应需求**：进程管理类

### 命令清单扩展
```
./pearl_hash start       # 启动（带锁 + 预检 + 启动验证 + 版本更新提示）
             stop [-y]   # 优雅关闭（SIGTERM → 10s → SIGKILL）
             restart     # stop + start
             pause       # 冻结 (SIGSTOP)，保留显存，释放算力，跑 LLM/其他镜像前调用
             resume      # 解冻 (SIGCONT)
             pre_run_llm # 等同 pause，额外输出可被 shell 捕获的退出码和提示语
             status [--brief]  # 详细状态 / 简要状态
             config      # 打印当前配置
             logs [N] [-f]     # tail -N / tail -f 查看日志
             metrics     # Prometheus 格式输出
             version     # 打印入口脚本 + 矿工程序版本 + 远程最新版对比
             check-update # 仅检查版本更新，不下载
             update [-y] # 下载最新版 miner，-y 跳过确认；wildrig 自动解压 tar.gz
             --version   # 入口脚本版本号
             --help      # 帮助
```

### 启动命令按 MINER_FLAVOR 策略模式生成
根据 MINER_FLAVOR 拼接底层执行命令，这样切换 flavor 不影响外层逻辑：

```bash
# MINER_FLAVOR=pearl（legacy）
PEARL_CMD="${BIN_DIR}/pearl-miner \
  --pool '${POOL_HOST}' \
  --user '${USER_ADDRESS}' \
  --worker '${WORKER_NAME}'"

# MINER_FLAVOR=wildrig（官方推荐 4090）
# 自动处理 stratum+tcp:// 前缀
[[ "${STRATUM_PREFIX_AUTO}" == "true" && "${POOL_HOST}" != stratum* ]] \
  && WILDRIG_URL="stratum+tcp://${POOL_HOST}" \
  || WILDRIG_URL="${POOL_HOST}"
WILDRIG_CMD="${BIN_DIR}/wildrig-multi \
  -a '${WILDRIG_ALGO}' \
  -o '${WILDRIG_URL}' \
  -u '${USER_ADDRESS}' \
  -w '${WORKER_NAME}' \
  -p x \
  --print-time '${WILDRIG_PRINT_TIME}' \
  --gpu-list '${GPU_DEVICES_CSV}' \
  --gpu-temp-limit '${MAX_GPU_TEMP}' \
  ${WILDRIG_WATCHDOG:+--watchdog} \
  ${WILDRIG_API_PORT:+--api-port ${WILDRIG_API_PORT}}"
```

### 启动验证流程（STARTUP_VERIFY_TIMEOUT_SEC=30）
时间轴：
- T+0s   根据 MINER_FLAVOR 生成命令 → 启动 nohup，写入 PID
- T+1s   首次检查 kill -0，存活则继续
- T+5s   扫描日志 / 读 API /health：检查 STARTUP_FAIL_KEYWORDS → 任一命中 = 立即失败清理
- T+10s  判定启动成功：MINER_FLAVOR=wildrig 优先 `curl 127.0.0.1:${WILDRIG_API_PORT}/health`；否则从日志 grep 对 flavor 正确的 STARTUP_VERIFY_KEYWORD
- T+15s / 20s / 25s   同上重试
- T+30s  超时仍未看到算力 → 警告但不强制 kill（可能首次 job 分配慢 / 初次任务难度高）

### 看门狗自动重启流程
两种实现思路，二选一：

- 方案 A：脚本内 while 循环。nohup 后 wait $pid，非 0 退出且 AUTO_RESTART=true 则 sleep 后重启。优点：零依赖，纯 bash；缺点：入口脚本本身不能退出，占用一个 bash 进程
- 方案 B：交给 systemd。pearl_hash start 直接前台运行 miner（不加 nohup），systemd 负责 Restart=。优点：工业标准，状态可被 systemctl status 识别；缺点：必须通过 systemd 启动，手动 ./pearl_hash start 没有自动重启

推荐同时支持。手动运行用 A，systemd 模式用 B（通过 PEARL_HASH_FOREGROUND=1 环境变量切换模式）。
若 MINER_FLAVOR=wildrig 且已开启 WILDRIG_WATCHDOG=true：外层 bash 看门狗依然保留，双重保险。

### 并发锁机制
```bash
# 使用 flock 原子性
LOCK_FILE="${RUN_DIR}/.start.lock"
exec 9>"$LOCK_FILE"
if ! flock -n 9; then
    warn "检测到另一个 start 操作正在进行，已自动跳过"
    exit 0
fi
# 脚本退出时自动释放锁（flock fd 伴随进程退出）
```

---

## 日志管理
**对应需求**：日志管理类

### 轮转算法（伪代码）
```bash
function rotate_logs() {
    # 0. 当前日志未超限直接返回
    [[ $(size_miner_log) <= $LOG_MAX_SIZE_MB*1024*1024 ]] && return 0

    # 1. 删除最旧的归档 miner.log.${LOG_ROTATE_KEEP}.gz
    rm -f "miner.log.${LOG_ROTATE_KEEP}.gz"

    # 2. 从大到小依次改名: .6.gz → .7.gz, .5.gz → .6.gz ...
    for i in $(seq $((LOG_ROTATE_KEEP-1)) -1 1); do
        [[ -f "miner.log.${i}.gz" ]] && mv "miner.log.${i}.gz" "miner.log.$((i+1)).gz"
    done

    # 3. 当前日志 → miner.log.1
    mv miner.log miner.log.1

    # 4. miner.log.1 → gzip → miner.log.1.gz（如 LOG_COMPRESS=true）
    [[ $LOG_COMPRESS == "true" ]] && gzip miner.log.1
}
```

### 运行时轮转触发时机
- start 启动前（保留原行为）
- status 每次调用时
- 看门狗循环中每 LOG_RUNTIME_CHECK_INTERVAL 秒一次

### WildRig 模式下日志优化
MINER_FLAVOR=wildrig 时：
- 建议开启 `--log-file logs/miner.log` + `--log-job`（记录 job 分配细节，便于排障）
- 摘要打印通过 `--print-time N` 控制频率，避免日志膨胀过快
- 即使有 HTTP API，仍保留 stats.jsonl 周期性落盘：防止 API 异常时历史数据丢失

### 结构化 stats.jsonl
每次扫描到算力摘要行（或从 WildRig API 拉取到），追加一行：
```json
{"ts":"2026-08-09T21:03:12+08:00","hashrate_total_hs":520500000000000,"gpu0_hs":262400000000000,"gpu1_hs":258100000000000,"accepted":1247,"rejected":3}
```
后续 status 计算 1h/6h/24h 均值、Prometheus 指标导出，都读这个文件而不是 grep 原始 miner.log；有 API 时优先读 API 并同样落盘。

---

## GPU 资源协调
**对应需求**：GPU 资源协调类 + 官方资料影响

> 核心前提：Pearl 采用纯算力型算法（非 Ethash 等显存密集型），无需加载 DAG，显存占用极小。与本机其他 GPU 服务（监控镜像/LLM/其他容器）的冲突主要体现在 **CUDA 核心算力争抢** 和 **温度/功耗**，而非显存 OOM。因此「显存阈值拒绝启动」是不必要的，但「暂停挖矿让路」依然很有价值。
>
> 若 MINER_FLAVOR=wildrig：可直接通过 `--temperature-limit/--temperature-start` 让 miner 原生响应温度，结合 `--gpu-intensity` 细配强度。

### 启动前 GPU 预检
预检目标：GPU 能不能用 / 有没有其他占算力的进程 / 温度是否合理

```bash
# nvidia-smi 查询：检查 GPU 是否存在 + 温度 + 功耗 + 利用率
nvidia-smi \
  --id="${gpu_id}" \
  --query-gpu=index,name,temperature.gpu,power.draw,utilization.gpu \
  --format=csv,noheader,nounits

# 同时查询是否有其他 GPU 计算进程（排除 kernel/Xorg / dcgm-exporter 等轻量进程）
nvidia-smi --query-compute-apps=pid,process_name,used_memory --format=csv,noheader
```

预检逻辑：
- GPU 设备存在且 nvidia-smi 可访问 → 通过
- 若检测到其他活跃的 compute 进程：
  - 先比对 GPU_IGNORE_PROCS 列表，监控进程 / Xorg 等轻量直接忽略
  - 匹配到重度进程（例如 LLM 推理容器、其他 miner）：
    - GPU_STRICT_EXCLUSIVE="true" → 打印具体 PID+进程名，拒绝启动
    - GPU_STRICT_EXCLUSIVE="false" → 仅打印警告（「检测到其他 GPU 进程 PID=xxx name=xxx，算力争抢可能导致双方性能下降」），由用户决策
- 若温度超过 MAX_GPU_TEMP + 10°C → 拒绝启动，提示过热
- 若 logs/ 所在分区剩余空间 < MIN_DISK_SPACE_MB → 打印磁盘空间警告
- （WildRig 专属）若 MAX_GPU_TEMP 合理：启动命令里自动映射到 `--temperature-limit`，无需额外实现外层温度驱动的自动暂停

### pause / resume / pre_run_llm 对比
- pause：SIGSTOP，进程停止（挂起），显存仍占用（Pearl 显存占用极小，可忽略），算力释放，矿池心跳超时可能断开
- stop：SIGTERM→KILL，进程退出，显存释放，算力释放，矿池正常断开
- pre_run_llm：等同 pause，额外打印明确的 LLM 启动提示，告诉用户 LLM 跑完后执行 ./pearl_hash resume。同时以退出码 0=成功暂停 / 非 0=暂停失败，便于外层 LLM 启动脚本条件判断（`./pearl_hash pre_run_llm || echo "暂停失败，请手动停矿"`）

---

## 状态监控
**对应需求**：状态监控类

### 数据源汇总
- PID / 运行时长 → ps -o etime= -p $PID
- 矿池连接状态 / 延迟 → 最近日志解析 + stats.jsonl + WildRig API（有则优先）
- 最近一次任务分配 / 致命错误 → miner.log 尾部反向 grep
- 钱包查询直达链接 → 固定前缀 + USER_ADDRESS 拼接

### WildRig 模式下优先走 API
若 MINER_FLAVOR=wildrig 且 WILDRIG_API_PORT>0：
- `curl 127.0.0.1:${WILDRIG_API_PORT}/hashrate` 直接拿单卡 / 总算力，不用正则
- `curl 127.0.0.1:${WILDRIG_API_PORT}/accepted` / `/rejected` 拿 shares 数量
- 更可靠、更快、不依赖日志格式稳定

---

## 可观测性
**对应需求**：可观测性类

### 数据源汇总
- 单卡算力 → grep miner.log 每 Hashrate GPU X 行；或 WildRig API
- GPU 温度/功耗/显存/风扇/利用率 → nvidia-smi query-gpu
- 1h/6h/24h 平均算力 → stats.jsonl 按时间窗口聚合
- 拒绝率 / 提交数 → stats.jsonl accepted/rejected 累计差值

### nvidia-smi 查询字段
```bash
nvidia-smi \
  --query-gpu=index,name,memory.used,memory.total,temperature.gpu,power.draw,fan.speed,utilization.gpu \
  --format=csv,noheader,nounits
```

### metrics 输出格式（Prometheus exposition format）
```
# HELP pearl_hash_miner_up Miner process running (1=running, 0=stopped)
# TYPE pearl_hash_miner_up gauge
pearl_hash_miner_up 1

# HELP pearl_hash_pid Miner process ID
# TYPE pearl_hash_pid gauge
pearl_hash_pid 12345

# HELP pearl_hash_miner_flavor Miner flavor (1=pearl legacy, 2=wildrig)
# TYPE pearl_hash_miner_flavor gauge
pearl_hash_miner_flavor{name="wildrig"} 2

# HELP pearl_hash_hashrate_bytes Hashrate per GPU in H/s
# TYPE pearl_hash_hashrate_bytes gauge
pearl_hash_hashrate_bytes{gpu="0",name="NVIDIA GeForce RTX 4090"} 2.624e14
pearl_hash_hashrate_bytes{gpu="1",name="NVIDIA GeForce RTX 4090"} 2.581e14
pearl_hash_hashrate_bytes{gpu="total"} 5.205e14

# HELP pearl_hash_gpu_memory_used_bytes GPU memory used in bytes
# TYPE pearl_hash_gpu_memory_used_bytes gauge
pearl_hash_gpu_memory_used_bytes{gpu="0"} 2.287e10
pearl_hash_gpu_memory_used_bytes{gpu="1"} 2.265e10

# HELP pearl_hash_gpu_temperature_celsius GPU temperature
# TYPE pearl_hash_gpu_temperature_celsius gauge
pearl_hash_gpu_temperature_celsius{gpu="0"} 72
pearl_hash_gpu_temperature_celsius{gpu="1"} 70

# HELP pearl_hash_gpu_power_watts GPU power draw
# TYPE pearl_hash_gpu_power_watts gauge
pearl_hash_gpu_power_watts{gpu="0"} 320.4
pearl_hash_gpu_power_watts{gpu="1"} 315.2

# HELP pearl_hash_shares_total Total shares
# TYPE pearl_hash_shares_total counter
pearl_hash_shares_total{result="accepted"} 1247
pearl_hash_shares_total{result="rejected"} 3
```

### 接入 node_exporter
项目已有 infra/monitoring/，只要：
- 确保 node_exporter 启动参数加上 --collector.textfile.directory=/var/lib/node_exporter/textfile_collector/
- 每分钟 cron 或 systemd timer 运行：/root/deAI/pearl_hash/pearl_hash metrics > /var/lib/node_exporter/textfile_collector/pearl_hash.prom
- 或若 MINER_FLAVOR=wildrig：直接让 Prometheus 拉 WildRig 原生 API（可能需要 exporter 转换格式，用 textfile 更简单）
- Grafana 直接用 PromQL 查询即可

---

## 挖矿软件版本检测与自更新
**对应需求**：挖矿软件版本管理类 + 官方资料分析（legacy V13 + WildRig Multi 0.49.6 + 官网 v6）

### 版本号识别策略
- 入口脚本版本：`readonly VERSION="x.x.x-pearl_hash"`，直接读取
- 本地 miner 版本：优先顺序
  1. `bin/miner.version` 纯文本文件（update 命令写入，同时记录 MINER_FLAVOR，最可靠）
  2. 回退：尝试 `bin/$MINER_BIN_NAME --version 2>&1` 解析输出
  3. 回退：以文件大小 + mtime 粗略标识（带警告）
- 远程最新版本：
  - 不再走 GitHub REST API（需要认证、有限流），改为直接 `curl -sL https://github.com/{repo}/releases` 抓取 HTML 页面
  - 用 `grep -oP 'releases/tag/[^"]+' | head -1` 提取最新 tag 名
  - 下载直链改为固定模板：`https://github.com/{repo}/releases/download/{tag}/wildrig-multi-linux-{tag}.tar.gz`
  - 彻底移除了 `python3` 和 `GITHUB_API_BASE` 依赖

### check-update 命令行为
```
$ ./pearl_hash check-update
────────────────────────────────────────
版本检查 (MINER_FLAVOR=wildrig)
────────────────────────────────────────
本地 miner:   0.49.6  (bin/miner.version)
官方发布:     0.49.6 (2026-07-20, WildRig Multi)
────────────────────────────────────────
✓ 已是最新版本
────────────────────────────────────────
官方提示:     pearlhash 已连续 8 个版本被 WildRig 重点优化
              kernel 建议值 2 (4090 默认)
              如需切回 legacy pearl-miner: .env 改 MINER_FLAVOR=pearl
```

### update 命令流程
1. 检查当前 miner 是否在运行；若在运行则提示先 stop
2. 从 GitHub releases 页面提取最新 tag
3. 按 `https://github.com/{repo}/releases/download/{tag}/...` 固定模板构建下载直链
4. wildrig：下载 tar.gz → 解压 → 安装到 `bin/wildrig-multi` + chmod +x
5. pearl：下载单文件 → 安装到 `bin/pearl-miner`
6. 旧版自动备份：`bin/wildrig-multi.bak.时间戳`
7. 写入 `bin/miner.version`（版本号 + flavor）
8. 生成 `bin/help.txt`（`wildrig-multi --help` 输出）

---

## 鲁棒性
**对应需求**：鲁棒性类

- 动态路径解析：所有路径以 `SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"` 为前缀，零硬编码
- 原子 PID 写入：`echo $$ > "${RUN_DIR}/.miner.pid.tmp" && mv "${RUN_DIR}/.miner.pid.tmp" "${RUN_DIR}/miner.pid"`
- 启动锁文件：见「进程守护与高可用」章节 flock 方案
- PID 僵尸清理：is_running() 中若 PID 文件存在但 kill -0 失败，自动 rm -f $PID_FILE，避免假死
- 全局参数解析：支持 -y/--yes（危险操作跳过确认）、--version（入口脚本版本）、--help（帮助）
- 子命令位置：`./pearl_hash [全局参数] <命令> [命令参数]`，例如 `./pearl_hash -y stop` / `./pearl_hash logs -f 200`
- set -euo pipefail：保留；grep 无匹配用 `|| true`；需要容忍失败的命令显式 `||`
- 三级输出函数：log（绿色 INFO） / warn（黄色 WARN） / err（红色 ERROR 到 stderr）

---

## 工程规范
**对应需求**：工程规范类

- 入口脚本 VERSION 常量 + 每个 lib/*.sh 顶部注释版本信息
- 完整中文注释：所有函数、配置项、默认值加注释；关键分支说明「为什么这样做」
- 模块化拆分：logrotate.sh / gpu_check.sh / health_check.sh / version_check.sh 可独立 source，也可单独 `bash lib/xxx.sh` 做单元调试
- .env 全参数中文注释：任何 .env 新增配置都必须同步在注释里说明默认值、可选值、影响范围
- 二进制可执行性：start 前检查 bin/$MINER_BIN_NAME 存在 + 可执行，无则自动 chmod +x；仍不存在则错误提示可能需要先 `./pearl_hash update`
- nvidia-smi 可用性：无 nvidia-smi 给出驱动安装提示；start 前 warn，status 可缺省 GPU 指标输出
- 矿池连通性：DNS 解析（可关） + TCP 端口（可关），失败时打印 .env 中配置的 NETWORK_HINT
- 磁盘空间：start / logrotate 前检查 logs 分区剩余空间，低于 MIN_DISK_SPACE_MB 警告

---

# 问题与解决

实现过程中遇到的坑以及对应解法，按日期先后顺序记录：

## 2026-08-10

### WildRig 命令行参数名错误
- **问题**：`--devices`、`--temperature-limit`、`--log-job`、`--api-bind`、`--no-nvml` 等参数 WildRig 0.49.9 均不识别，启动时报 `unrecognized option`
- **根因**：参数名凭记忆编写，未对照 WildRig 实际 `--help` 输出
- **解决**：以 `bin/help.txt`（`wildrig-multi --help` 输出）为准，修正如下：
  - `--devices` → `--gpu-list`
  - `--temperature-limit` → `--gpu-temp-limit`
  - `--log-job` → 删除（不存在此参数）
  - `--api-bind` → 删除（不存在此参数，仅 `--api-port`）
  - `--no-nvml` → 删除（不存在此参数）
  - `--log-file` → 删除（shell 重定向已写入日志，避免重复输出）
- **教训**：任何外部工具的参数名必须对照其官方 `--help` 输出，不能凭记忆或 README 二手信息

### update 后 bin/ 缺失 help.txt
- **问题**：`update` 命令只下载二进制和写 `miner.version`，缺少 `help.txt`
- **根因**：`help.txt` 原先是从旧目录手动拷贝过去的，`update` 流程未覆盖
- **解决**：在 `cmd_update.sh` 安装完成后增加一步：`"$dst_bin" --help > "${BIN_DIR}/help.txt"`

### 日志重复输出
- **问题**：`miner.log` 中每行日志出现两次
- **根因**：shell 重定向（`>> "$LOG_FILE" 2>&1`）和 WildRig 自己的 `--log-file` 同时写同一个文件
- **解决**：移除命令中的 `--log-file` 参数，只靠 shell 重定向写入日志

### GitHub API 限流 / 版本检查失败
- **问题**：`check-update` 报 `curl: (22) The requested URL returned error: 403`，`python3` 解析空响应报 `JSONDecodeError`
- **根因**：版本检查走的是 `https://api.github.com`（GitHub REST API），不带 User-Agent 会被直接 403 拒绝。GitHub API 本身有频率限制且需要认证，不适合脚本场景
- **解决**：放弃 GitHub API，改为直接 `curl -sL https://github.com/{repo}/releases` 抓取 HTML 页面，用 `grep -oP 'releases/tag/[^"]+'` 提取版本号。下载直链也从 API assets 字段构建改为固定 URL 模板：`https://github.com/{repo}/releases/download/{tag}/wildrig-multi-linux-{tag}.tar.gz`。彻底移除 `python3` 和 `GITHUB_API_BASE` 依赖

---

# 更新说明

- 2026-08-09
  - 从原 /root/deAI/pearl 项目发现代码重复、硬编码配置、日志轮转缺失、无 GPU 协调、无版本管理等问题
  - 抓取并整理官方资料：pearlhash.xyz 矿池、pearlhash/pearlhash-miner（legacy）、andru-kun/wildrig-multi（官方推荐）
  - 重点分析 WildRig Multi：连续 8 个 release 针对 pearlhash 优化，4090 官方推荐，约 0.75% devfee，原生 API/看门狗/温度控制等运维特性丰富；结论为推荐选用，同时保留 MINER_FLAVOR 兼容 legacy miner
  - 形成完整文档：资料参考 → 需求分析 → 方案设计 → 问题与解决四大部分
  - 需求按配置管理、目录结构、进程管理、日志管理、GPU 资源协调、状态监控、可观测性、挖矿软件版本管理、鲁棒性、工程规范共 10 大类拆分
  - 方案围绕目录结构、配置分离、进程守护、日志轮转、GPU 协调、状态监控、可观测性、版本更新、鲁棒性、工程规范共 10 个对应模块展开

- 2026-08-10
  - 入口脚本模块化重构：pearl_hash 从 1257 行瘦身到 ~430 行，业务逻辑按功能拆分到 lib/cmd_*.sh 各模块
  - 目录整理：wildrig/ 清理，二进制统一放到 bin/，wildrig-multi 为标准二进制名
  - WildRig 参数修正：--devices→--gpu-list、--temperature-limit→--gpu-temp-limit 等，全部以 bin/help.txt 为准
  - 版本检测改为直接 curl GitHub releases 页面 HTML + grep 提取 tag，摆脱 GitHub REST API（避免 403/限流），移除 python3 和 GITHUB_API_BASE 依赖
  - update 命令增加 help.txt 自动生成（安装后执行 --help 写入）
  - status 重构：优先 WildRig HTTP API 数据（awk 解析），降级 nvidia-smi。输出精简为一张紧凑面板
  - 新增 monitor 命令：封装 watch，实现实时监控面板（默认 5s 刷新，Ctrl+C 退出）
  - 温度保护告警：status 展示最近 3 次降频事件详情（时间、GPU、温度/功耗/算力、恢复时间）
  - 温度上限从 85°C 调至 90°C（GPU#1 在 82°C 反复触发降频）
  - stop 命令改为直接停止，不再询问确认
  - 收益查询链接修正：/#lookup?address= → /account/

