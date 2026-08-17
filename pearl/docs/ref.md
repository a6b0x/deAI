# 资料参考

## 官方链接

| 资源 | URL |
|------|-----|
| Kryptex 矿池（Pearl） | `https://pool.kryptex.com/zh-cn/prl` |
| KRig（Kryptex 开发，0% devfee） | `https://github.com/kryptex/krig-miner` |
| SRBMiner-MULTI | `https://github.com/doktor83/SRBMiner-MULTI` |
| PeakMiner | `https://github.com/peakminer/PeakMiner` |
| ForgeMiner | `https://github.com/0xHashRaptor/ForgeMiner` |
| ARCMiner | `https://github.com/arcminer/ARCMiner` |
| Fl4shMiner | `https://github.com/fl4shminer/Fl4shMiner` |
| Pearl Desktop Wallet | Pearl 官方钱包 |

## 矿池基本信息

| 项目 | 内容 |
|------|------|
| 算法 | PearlHash |
| 矿池算力 | 4.37 EH/s |
| 矿工数 | 3,322 |
| 最低支付 | 1 PRL |
| PPS+ 费率 | 2% |
| SOLO 费率 | 1% |

## 连接地址

| 区域 | 地址 |
|------|------|
| 全球 | `prl.kryptex.network:7048` |
| 欧洲 | `prl-eu.kryptex.network:7048` |
| 北美 | `prl-us.kryptex.network:7048` |
| 南美 | `prl-br.kryptex.network:7048` |
| 新加坡 | `prl-sg.kryptex.network:7048` |
| 中国（香港） | `prl-hk.kryptex.network:7048` |
| 俄罗斯 | `prl-ru.kryptex.network:7048` |
| 中东 | `prl-ae.kryptex.network:7048` |

> 钱包格式：`wallet/worker` 或 `username/worker`
> SOLO 挖矿格式：`solo:wallet`

## 矿工选型速查

| 矿工 | 版本要求 | 适用场景 | Devfee | 备注 |
|------|---------|---------|--------|------|
| **PeakMiner**（Docker 首选） | ≥ 2.9.0 | NVIDIA sm_60+ / AMD RDNA 1+（Pearl 仅 NVIDIA sm_75+） | **2%** | 官方 Docker 镜像，算力最高 |
| **ForgeMiner**（Docker 备选） | latest | NVIDIA 全系（Pascal → Blackwell + Hopper） | **2%** | 官方 Docker 镜像 `hashraptor/forge`，闭源，CUDA Driver API 原生实现 |
| **KRig**（二进制首选） | ≥ 1.2.0 | AMD RDNA 2/3/4、CDNA 4、NVIDIA RTX 2000-5000 | **0%** | Kryptex 官方开发，gzip 压缩 |
| **SRBMiner-MULTI** | ≥ 3.5.3 | AMD / NVIDIA 通用 | 约 1-2%（视算法） | 老牌矿工，社区活跃 |
| **ARCMiner** | ≥ 0.3.1 | AMD / NVIDIA 通用 | 未注明 | 较新的矿工 |
| **Fl4shMiner** | ≥ 1.2.7 | AMD / NVIDIA 通用 | 未注明 | — |

> ⚠️ **重要**：Pearl 团队已更改算法，必须升级矿工程序到指定版本以上，旧版软件将提交 **100% 无效份额**。

### 选型建议

| 对比维度 | PeakMiner（Docker） | KRig（二进制） |
|---------|---------------------|----------------|
| 部署难度 | ⭐ 一行 `docker run` | ⭐⭐ 需下载 + 解压 |
| Devfee | **2%** | **0%** |
| 4090 算力 | **291.2 TH/s** | ~254 TH/s |
| 5090 算力 | **376.2 TH/s** | ~335 TH/s |
| 矿池流量 | 无压缩 | gzip 压缩，减少 **80%** |
| 开发者 | 第三方（peakminer） | Kryptex 官方 |
| 运维特性 | Docker 原生重启策略 | 需自行配 nohup / systemd |
| API 监控 | ✅ `--api-port 4068` | ✅ `--api-port` |
| GPU 超频 | ✅ 内置参数 | ❌ 需外部工具 |
| GPU 兼容 | NVIDIA sm_75+ (RTX 20xx+)、AMD 仅 CSD/ALP | AMD RDNA 2/3/4 + NVIDIA RTX 2000-5000 |

**结论**：两者各有优势，按需选择：

- **追求省心 + 高算力** → **PeakMiner Docker**：4090 算力比 KRig 高约 15%（291 vs 254 TH/s），但 devfee 2%。一行命令部署，Docker 自动重启，适合不想折腾的场景
- **追求 0% devfee + 省流量** → **KRig 二进制**：每 100 PRL 收益多拿 2 PRL，gzip 压缩省 80% 流量。适合长期跑、带宽受限的场景
- **老卡用户（GTX 16xx 等）** → **SRBMiner-MULTI**：Pearl 对 GPU 架构有要求，PeakMiner 需 sm_75+，KRig 需 RTX 2000+，老卡只能用 SRBMiner

---

# 当前部署（2026-08-12：Docker Compose 双矿工对比）

本机两张 RTX 4090 分别运行 PeakMiner 和 ForgeMiner 进行实测对比，由 `/root/deAI/pearl/docker-compose.yml` 统一管理：

| | GPU 0 | GPU 1 |
|---|---|---|
| 矿工 | PeakMiner v2.9.0 | ForgeMiner（latest） |
| 容器 | `kryptex-prl-peakminer` | `kryptex-prl-forgeminer` |
| 镜像 | `peakminer/peakminer:latest` | `hashraptor/forge:latest` |
| 矿池 | `prl.kryptex.network:8048`（SSL） | `prl.kryptex.network:7048`（TCP） |
| Worker | `.../peak` | `.../forge` |
| Devfee | 2% | 2% |
| 文件日志 | `pearl/logs/miner.log` | `pearl/logs/forge.log`（tee 落盘） |
| 监控 API | `http://127.0.0.1:4068/summary` | `http://127.0.0.1:7777/summary`（另有 `/metrics` Prometheus 端点） |

对比口径：两者均为 PPS+ 模式、同一钱包、同一全球节点，**以矿池后台按 worker（peak/forge）统计的 24h 平均收益为准**。注意 GPU 1 本身散热较差（温度比 GPU 0 高约 8°C），长时间对比后可交换两卡的矿工再测一轮消除体质/散热影响。

**首轮实测（2026-08-12，无超频）**：PeakMiner 288.2 TH/s（641.8 GH/W） vs ForgeMiner 278.9~282 TH/s（621.1 GH/W），PeakMiner 高约 3%，能效略优，两者 0 拒绝。

**常用命令**：

```bash
cd /root/deAI/pearl
docker compose up -d                 # 启动/应用变更
docker compose down                  # 停止全部
docker compose logs -f forgeminer    # 看某个服务日志
tail -f logs/miner.log               # PeakMiner 文件日志
tail -f logs/forge.log               # ForgeMiner 文件日志
docker restart kryptex-prl-forgeminer  # 单独重启某个矿工
```

---

# 手动下载与测试（快速上手）

以下步骤完全手动操作，不需要任何自动化脚本，适合初次验证。

## 方式一：Docker（首选，最简部署）

一行命令启动，无需下载二进制、配置环境，自动重启。

> **注意**：Docker 方式使用 PeakMiner（非 KRig）。PeakMiner 对 Pearl 算法优化更好（4090 算力 291.2 TH/s vs KRig 254 TH/s），但 devfee 为 2%（KRig 为 0%）。追求极致省心选 Docker，追求 0% devfee 选下面方式二的 KRig 二进制。

### 前置依赖

Docker 访问 GPU 需要宿主机安装 NVIDIA 驱动 + **NVIDIA Container Toolkit**。仅装 Docker 是不够的（`--gpus all` 依赖 nvidia-container-runtime）。

```bash
# 1. 确认 NVIDIA 驱动已安装
nvidia-smi

# 2. 安装 NVIDIA Container Toolkit（Ubuntu/Debian）
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey \
  | gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list \
  | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' \
  | tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
apt-get update && apt-get install -y nvidia-container-toolkit
nvidia-ctk runtime configure --runtime=docker
systemctl restart docker

# 3. 验证 GPU 在容器内可见
docker run --rm --gpus all nvidia/cuda:12.6.0-base-ubuntu24.04 nvidia-smi
```

### 启动容器

```bash
# 拉取最新镜像
docker pull peakminer/peakminer:latest

# 创建日志目录
mkdir -p /root/deAI/pearl/logs

# SOLO 模式（费率 1%）—— 含日志持久化 + API + 外部 DNS
# ⚠️ 使用 --network host，API 绑定在宿主机 127.0.0.1:4068
docker run -d \
  --gpus all \
  --restart=unless-stopped \
  --name kryptex-prl-peakminer \
  --network host \
  -v /root/deAI/pearl/logs:/var/log/peakminer \
  --dns 8.8.8.8 \
  --dns 1.1.1.1 \
  peakminer/peakminer:latest \
  --coin pearl \
  -o stratum+ssl://prl.kryptex.network:8048 \
  -u solo:prl1pldsjzegmcujgsp5rlhslp4gyg6zvkcqq2czmpqrptezay0pcmd8sveydvl/agent \
  -f /var/log/peakminer/miner.log \
  --log-append \
  --api-port 4068 \
  --report-stats

# PPS+ 模式（费率 2%，去掉 solo: 前缀）
docker run -d \
  --gpus all \
  --restart=unless-stopped \
  --name kryptex-prl-peakminer \
  --network host \
  -v /root/deAI/pearl/logs:/var/log/peakminer \
  --dns 8.8.8.8 \
  --dns 1.1.1.1 \
  peakminer/peakminer:latest \
  --coin pearl \
  -o stratum+ssl://prl.kryptex.network:8048 \
  -u prl1pldsjzegmcujgsp5rlhslp4gyg6zvkcqq2czmpqrptezay0pcmd8sveydvl/agent \
  -f /var/log/peakminer/miner.log \
  --log-append \
  --api-port 4068 \
  --report-stats
```

| 参数 | 说明 |
|------|------|
| `-d` | 后台运行 |
| `--gpus all` | 使用所有 GPU（指定单卡用 `--gpus '"device=0,1"'`） |
| `--restart=unless-stopped` | 崩溃/重启后自动拉起 |
| `--name kryptex-prl-peakminer` | 容器名，方便管理 |
| `--network host` | 使用宿主机网络栈（替代 `-p` 端口映射）。PeakMiner API 硬编码绑定 `127.0.0.1`，bridge 模式下 `-p` 无法转发，必须用 host 模式才能从外部访问 API |
| `-v /root/deAI/pearl/logs:/var/log/peakminer` | 日志持久化，容器删除后日志不丢失 |
| `--dns 8.8.8.8 --dns 1.1.1.1` | **指定外部 DNS**，解决容器内部分矿池域名解析超时问题 |
| `peakminer/peakminer:latest` | 使用最新镜像，确保算法兼容 |
| `--coin pearl` | **必需参数**，指定币种为 Pearl |
| `-o` | 矿池地址，推荐用全球节点 `prl.kryptex.network:8048`（SSL）；区域节点可能 DNS 不通 |
| `-u` | 钱包/矿工名。PeakMiner **原样发送**，用 `/` 分隔钱包和矿工名；SOLO 模式加 `solo:` 前缀 |
| `-f /var/log/peakminer/miner.log` | 日志写入文件（容器内路径，已通过 `-v` 映射到宿主机） |
| `--log-append` | 追加模式写日志（重启不覆盖历史日志） |
| `--api-port 4068` | 开启 HTTP 统计 API，默认绑定 `127.0.0.1` |
| `--report-stats` | 向矿池上报挖矿统计信息 |

> **关于矿池节点选择**：实测香港节点 `prl-hk` 在容器内 DNS 解析超时，全球节点 `prl.kryptex.network` 连接正常（ping ~170ms）。建议先用全球节点，或通过 `--dns` 指定外部 DNS 后再试区域节点。
>
> **关于 `-u` 和 `--worker`**：PeakMiner 的 `-u` 参数是原样发送给矿池的，不会被拆分。如果 `-u` 中已包含 `/` 或 `.`，则 `--worker` 参数会被忽略。所以推荐直接用 `wallet/worker` 格式写在 `-u` 里，不用单独的 `--worker`。

**常用管理命令**：

```bash
# 查看实时日志（容器 stdout/stderr）
docker logs -f kryptex-prl-peakminer

# 查看最近 50 行
docker logs --tail 50 kryptex-prl-peakminer

# 查看宿主机持久化日志文件
tail -f /root/deAI/pearl/logs/miner.log

# 查看 API 统计（容器启动后约 60s 才有数据）
curl http://localhost:4068/

# 停止挖矿
docker stop kryptex-prl-peakminer

# 重新启动
docker start kryptex-prl-peakminer

# 删除容器（先停止，日志因 -v 映射不会丢失）
docker rm -f kryptex-prl-peakminer
```

> **为什么 Docker 用 PeakMiner 而不是 KRig？** Kryptex 矿池页面的 Docker 选项默认使用 PeakMiner，该镜像已在 Docker Hub 发布。KRig 目前没有官方 Docker 镜像。两者都是 Kryptex 矿池官方推荐的矿工，且 PeakMiner 在 Pearl 算法上算力更高（4090: 291.2 TH/s vs KRig 254 TH/s）。

---

## 方式二：KRig 二进制（次选，0% devfee）

直接运行二进制，无 Docker 开销，适合对容器不熟悉或追求极简的场景。

### 1. 下载 KRig

```bash
mkdir -p /root/deAI/kryptex/bin && cd /root/deAI/kryptex/bin

# 下载最新版 v1.2.0（2026-08-11）
wget https://github.com/kryptex/krig-miner/releases/download/v1.2.0/krig-miner-1.2.0-linux-x64.tar.gz

# 解压
tar xzf krig-miner-1.2.0-linux-x64.tar.gz

# 验证
./krig-miner --version
```

### 2. 前台启动测试

```bash
cd /root/deAI/kryptex/bin

# SOLO 模式（费率 1%）
./krig-miner \
  --url stratum+ssl://prl-hk.kryptex.network:8048 \
  --user solo:prl1pldsjzegmcujgsp5rlhslp4gyg6zvkcqq2czmpqrptezay0pcmd8sveydvl/agent

# PPS+ 模式（费率 2%，去掉 solo:）
./krig-miner \
  --url stratum+ssl://prl-hk.kryptex.network:8048 \
  --user prl1pldsjzegmcujgsp5rlhslp4gyg6zvkcqq2czmpqrptezay0pcmd8sveydvl/agent
```

**预期输出**：启动后应看到 GPU 识别信息、矿池连接成功、开始接收任务、算力摘要行。按 `Ctrl+C` 退出。

### 3. 后台运行（生产环境）

```bash
cd /root/deAI/kryptex/bin
mkdir -p /root/deAI/pearl/logs

# nohup 后台运行
nohup ./krig-miner \
  --url stratum+ssl://prl-hk.kryptex.network:8048 \
  --user solo:prl1pldsjzegmcujgsp5rlhslp4gyg6zvkcqq2czmpqrptezay0pcmd8sveydvl/agent \
  > /root/deAI/pearl/logs/miner.log 2>&1 &

# 记录 PID
echo $! > /root/deAI/kryptex/run/miner.pid

# 查看实时日志
tail -f /root/deAI/pearl/logs/miner.log
```

---

## 方式三：PeakMiner 二进制（备选，Docker 的裸机替代）

不想用 Docker 但想要 PeakMiner 的高算力，可以直接跑二进制。

### 1. 下载

```bash
mkdir -p /root/deAI/kryptex/bin && cd /root/deAI/kryptex/bin

wget https://github.com/peakminer/peakminer/releases/download/v2.9.0/peakminer-2.9.0-linux-x86_64 -O peakminer
chmod +x peakminer
./peakminer --version
```

### 2. 启动

```bash
# SOLO 模式（费率 1%）
./peakminer \
  --coin pearl \
  -o stratum+ssl://prl-hk.kryptex.network:8048 \
  -u solo:prl1pldsjzegmcujgsp5rlhslp4gyg6zvkcqq2czmpqrptezay0pcmd8sveydvl/agent

# PPS+ 模式（费率 2%）
./peakminer \
  --coin pearl \
  -o stratum+ssl://prl-hk.kryptex.network:8048 \
  -u prl1pldsjzegmcujgsp5rlhslp4gyg6zvkcqq2czmpqrptezay0pcmd8sveydvl/agent

# 后台运行
nohup ./peakminer --coin pearl -o ... -u ... > /root/deAI/pearl/logs/miner.log 2>&1 &
```

> **`-u` 注意事项**：PeakMiner 将 `-u` 的值**原样发送**给矿池。如果 `-u` 中已含 `/` 或 `.`，则 `--worker` 参数会被忽略。建议直接用 `wallet/worker` 格式写在 `-u` 里。

---

## 方式四：SRBMiner-MULTI 二进制（老卡备选）

如果你的 GPU 不在 PeakMiner/KRig 支持范围（如 GTX 16xx），可用 SRBMiner。

### 1. 下载

```bash
cd /root/deAI/kryptex/bin
wget https://github.com/doktor83/SRBMiner-MULTI/releases/download/2.6.9/SRBMiner-Multi-2-6-9-Linux.tar.gz
tar -xzf SRBMiner-Multi-2-6-9-Linux.tar.gz
cd SRBMiner-Multi-2-6-9
chmod +x SRBMiner-MULTI
./SRBMiner-MULTI --version
```

### 2. 启动

```bash
# SOLO 模式（费率 1%）
./SRBMiner-MULTI \
  --algorithm pearlhash \
  --pool prl-hk.kryptex.network:7048 \
  --wallet solo:prl1pldsjzegmcujgsp5rlhslp4gyg6zvkcqq2czmpqrptezay0pcmd8sveydvl \
  --worker agent \
  --password x

# PPS+ 模式（费率 2%）
./SRBMiner-MULTI \
  --algorithm pearlhash \
  --pool prl-hk.kryptex.network:7048 \
  --wallet prl1pldsjzegmcujgsp5rlhslp4gyg6zvkcqq2czmpqrptezay0pcmd8sveydvl \
  --worker agent \
  --password x
```

> **注意**：SRBMiner 使用 TCP 端口 7048，钱包和矿工名分开传参（`--wallet` + `--worker`），与 PeakMiner/KRig 的格式不同。

---

## 日志解读

以 PeakMiner v2.9.0 双卡 RTX 4090 PPS+ 模式为例：

### 启动阶段

```
INFO peakminer/2.9.0 — coin=pearl wallet=prl1.../agent worker= devices=2 legacy_auth=false dev_fee=2.0%
INFO API listening on http://127.0.0.1:4068/summary
INFO connected prl.kryptex.network:8048  diff —  ping 419ms
INFO new job a9aab31c_2097152
INFO vardiff 9.01 PH
```

| 字段 | 含义 |
|------|------|
| `coin=pearl` | 当前币种 |
| `dev_fee=2.0%` | PeakMiner 抽成，挖 1 小时约 1 分 12 秒给开发者 |
| `devices=2` | 检测到 2 张 GPU |
| `ping 419ms` | 到矿池延迟，< 200ms 理想，> 500ms 需换节点 |
| `new job` | 矿池下发了新任务，正常 |
| `vardiff 9.01 PH` | 矿池根据算力自动分配的难度（PH = PetaHash = 10^15 H） |

### 每条 share 提交

```
accepted   GPU 0  lat 420ms  diff 9.01 PH  effort 46%
```

| 字段 | 含义 |
|------|------|
| `accepted` | ✅ 有效提交（`invalid` 或 `rejected` 则有问题） |
| `GPU 0` | 哪张卡提交的 |
| `lat 420ms` | 往返延迟（矿池发任务 → 算出结果 → 提交） |
| `diff 9.01 PH` | 这个 share 的目标难度 |
| `effort 46%` | 努力程度：实际耗时 ÷ 预期耗时。**< 100% = 运气好，> 100% = 运气差** |

### 摘要面板（每 60s 打印）

```
pool prl.kryptex.network:8048    uptime 00:01:00    ping 369ms
diff 9.01 PH    last share 8s ago    eta 16s    effort 47%    luck(1h/24h) 156%/156%

GPU  Name        Hashrate  Shares ok/inv   Temp   Fan    Pwr        Perf      Mclk      Pclk
───  ────────  ──────────  ─────────────  ─────  ────  ─────  ──────────  ────────  ────────
  0  RTX 4090  289.7 TH/s       1 / 0      78°C   89%   449W  645.2 GH/W  10251MHz   2310MHz
  1  RTX 4090  259.7 TH/s       1 / 0      87°C  100%   408W  636.6 GH/W  10251MHz   2070MHz
───  ────────  ──────────  ─────────────  ─────  ────  ─────  ──────────  ────────  ────────
Total          549.4 TH/s       2 / 0     eff 100.0%    857W  641.1 GH/W
```

#### 第一行（矿池/整体状态）

| 字段 | 含义 |
|------|------|
| `uptime` | 已运行时长 |
| `ping` | 当前矿池延迟 |
| `diff` | 当前任务难度 |
| `last share Xs ago` | 距离上次提交 share 的时间，持续 > 5min 需关注 |
| `eta 16s` | 按当前算力预计多久找到一个 share |
| `effort 47%` | 当前这个 share 的努力程度，< 100% = 运气好 |
| `luck(1h/24h)` | **运气指数**：= 实际耗时 ÷ 理论耗时。**> 100% = 运气差**（花了更久），**< 100% = 运气好**。PPS+ 模式下运气不影响收益，但长期 > 200% 可能说明网络或算力不稳定 |

#### GPU 表头含义

| 列 | 含义 | 正常范围（4090） |
|------|------|------|
| `Hashrate` | 实时算力 | 280-292 TH/s |
| `Shares ok/inv` | 累计有效/无效 share | inv 应为 0，偶发 1-2 个可接受 |
| `Temp` | GPU 核心温度 | **< 80°C 理想**，80-85°C 可接受，> 85°C ⚠️ |
| `Fan` | 风扇转速 % | 与温度正相关，100% 说明散热到极限 |
| `Pwr` | 实时功耗（W） | 400-450W |
| `Perf` | 能效（GH/W） | 630-650 GH/W |
| `Mclk` | 显存频率（MHz） | ~10251 MHz |
| `Pclk` | 核心频率（MHz） | ~2300 MHz（温度过高会自动降频） |
| `eff 100.0%` | 总算力有效占比 | 100% 最佳，< 99% 需查原因 |

#### ⚠️ 异常信号速查

| 现象 | 可能原因 | 排查方向 |
|------|---------|---------|
| `invalid` 或 `rejected` 持续 > 1% | 版本过旧/超频不稳 | 升级矿工、降超频 |
| `Temp > 85°C` 且 `Fan 100%` | 散热不足 | 清灰、改善风道、降功耗 |
| `Pclk` 明显偏低（< 2000 MHz） | 温度过高触发降频 | 加 `--gpu-temp-stop` 限温 |
| 两卡算力差距 > 10% | 散热不均或体质差异 | 检查 PCIe 插槽散热、调功耗 |
| `luck` 长期 > 200% | 网络丢包或算力波动 | 换区域节点、检查 `ping` |
| `timed out connecting` | DNS 或网络不通 | 加 `--dns`、换节点 |

---

## PPS+ vs SOLO 模式对比

| 模式 | 原理 | 费率 | 适合谁 |
|------|------|------|--------|
| **PPS+**（默认） | 按贡献算力稳定分账，收益可预期 | **2%** | 大多数矿工，追求稳定收益 |
| **SOLO** | 独立爆块，爆一块独拿全部奖励，不爆则零收益 | **1%** | 算力极大或有「赌运气」心态 |

简单说：PPS+ 是「细水长流，每天都有」，SOLO 是「要么不开张，开张吃很久」。以 Kryptex 当前 4.37 EH/s 的全网算力来看，单卡 4090（约 0.5 TH/s）SOLO 爆块的概率极低，**一般不建议小算力用户使用 SOLO 模式**。

**切换方法**：无论 Docker、KRig 还是 SRBMiner，只需在钱包地址前加 `solo:` 前缀即可，其余参数不变。费率自动从 2% 降为 1%。

---

## 常用管理命令速查

### Docker 方式

| 目的 | 命令 |
|------|------|
| 查看实时日志（stdout） | `docker logs -f kryptex-prl-peakminer` |
| 查看持久化日志文件 | `tail -f /root/deAI/pearl/logs/miner.log` |
| 查看最近 50 行 | `docker logs --tail 50 kryptex-prl-peakminer` |
| 查看 API 统计 | `curl http://localhost:4068/` |
| 停止挖矿 | `docker stop kryptex-prl-peakminer` |
| 启动挖矿 | `docker start kryptex-prl-peakminer` |
| 重启 | `docker restart kryptex-prl-peakminer` |
| 删除容器 | `docker rm -f kryptex-prl-peakminer` |
| 查看 GPU | `nvidia-smi` 或 `watch -n 1 nvidia-smi` |
| 收益查询 | `https://pool.kryptex.com/zh-cn/prl` |

### KRig 二进制方式

| 目的 | 命令 |
|------|------|
| 验证二进制 | `./krig-miner --version` |
| 查看帮助 | `./krig-miner --help` |
| 前台运行 | 见上面"方式二" |
| 后台运行 | `nohup ./krig-miner ... > logs/miner.log 2>&1 &` |
| 查看日志 | `tail -f /root/deAI/pearl/logs/miner.log` |
| 查进程 | `ps aux \| grep krig` |
| 终止挖矿 | `pkill krig-miner` |
| 查看 GPU | `nvidia-smi` 或 `watch -n 1 nvidia-smi` |

---

## 区域选择建议

| 位置 | 推荐节点 | 地址 |
|------|---------|------|
| 中国大陆 | 香港 | `prl-hk.kryptex.network:7048` |
| 东南亚 | 新加坡 | `prl-sg.kryptex.network:7048` |
| 欧洲 | 欧洲 | `prl-eu.kryptex.network:7048` |
| 北美 | 北美 | `prl-us.kryptex.network:7048` |
| 俄罗斯 | 俄罗斯 | `prl-ru.kryptex.network:7048` |
| 不确定 | 全球 | `prl.kryptex.network:7048` |

---

## ⚠️ 重要：算法升级提醒

Pearl 团队已更改算法，**所有矿工必须使用最新版本**，旧版将提交 **100% 无效份额**：
- KRig：使用最新版
- SRBMiner-MULTI ≥ 3.5.3
- PeakMiner ≥ 2.9.0
- ARCMiner ≥ 0.3.1
- Fl4shMiner ≥ 1.2.7

**验证方法**：启动后观察 rejected 比例，正常应 < 1%。若 rejected 持续 > 10%，说明版本不对，需升级。

---

## PeakMiner 关键命令选项速查

> PeakMiner 是 Docker 方式的底层矿工，v2.9.0，devfee 2%。

### 核心必填

| 参数 | 环境变量 | 说明 | 示例 |
|------|---------|------|------|
| `-c, --coin` | `PEAK_COIN` | **必需**，币种名 | `--coin pearl` |
| `-o, --url` | `PEAK_POOL` | 矿池地址，可重复多个做故障转移 | `-o stratum+ssl://prl-hk.kryptex.network:8048` |
| `-u, --user` | `PEAK_WALLET` | 钱包地址，**原样发送**不拆分 | `-u solo:prl1xxx.../agent` |
| `-p, --password` | `PEAK_PASSWORD` | 矿池密码（默认 `x`） | `-p x` |

> **关于 `-u`**：PeakMiner 原样发送 `-u` 的值，矿工名用 `/` 分隔写在 `-u` 里即可（如 `wallet/worker`）。如果 `-u` 中已含 `/` 或 `.`，则 `--worker` 参数会被忽略。

### 运维常用

| 参数 | 说明 | 建议值 |
|------|------|--------|
| `-d, --devices` | 指定 GPU 编号 | `-d 0,1`（默认 `all`） |
| `-i, --status-interval` | 状态打印间隔（秒） | `-i 30`（默认 60） |
| `-j, --job-timeout` | 任务超时重连（秒） | 默认 180 |
| `--keepalive` | 定期发送 mining.ping 保活 | 建议开启 |
| `-a, --api-port` | HTTP API 端口（默认 4068） | `--api-port 4068`（0=禁用） |
| `--report-stats` | 向矿池上报统计信息 | 建议开启 |

### GPU 超频参数（每 GPU 设置）

| 参数 | 说明 | 示例 |
|------|------|------|
| `--gpu-coreN <MHz>` | 核心频率偏移 | `--gpu-core0 150` |
| `--gpu-lcoreN <MHz>` | 核心频率锁定 | `--gpu-lcore0 2500` |
| `--gpu-memN <MHz>` | 显存频率偏移 | `--gpu-mem0 1000` |
| `--gpu-lmemN <MHz>` | 显存频率锁定 | `--gpu-lmemN 10500` |
| `--gpu-powerN <W\|%>` | 功耗限制 | `--gpu-power0 300` 或 `--gpu-power0 80%` |
| `--gpu-fanN <%>` | 风扇转速（0-100%） | `--gpu-fan0 80` |
| `--gpu-fan-targetN <°C>` | 闭环风扇目标温度 | `--gpu-fan-target0 70` |
| `--gpu-temp-stopN <°C>` | 暂停 GPU 温度阈值 | `--gpu-temp-stop0 85` |
| `--gpu-temp-startN <°C>` | 恢复 GPU 温度阈值 | `--gpu-temp-start0 70` |

### 日志参数

| 参数 | 说明 |
|------|------|
| `-l, --log-level` | 日志级别（默认 `info`） |
| `-f, --log-file` | 日志文件路径 |
| `--log-append` | 追加模式写日志 |

### 算力参考（pearlhash，默认超频）

| GPU | 算力 | 能效 |
|------|------|------|
| H200 | 643.0 TH/s | 924 GH/W |
| RTX 5090 | 376.2 TH/s | 654 GH/W |
| RTX 4090 | 291.2 TH/s | 649 GH/W |
| RTX 5080 | 215.2 TH/s | 615 GH/W |
| RTX 4080 SUPER | 203.0 TH/s | 636 GH/W |
| RTX 3090 Ti | 150.6 TH/s | 336 GH/W |
| RTX 3070 Ti | 98.4 TH/s | 318 GH/W |

---

## KRig 关键特性

| 特性 | 说明 |
|------|------|
| Devfee | **0%**（Kryptex 官方开发，无抽成） |
| 支持 GPU | AMD RDNA 2/3/4、CDNA 4、集成 RDNA 3.5（需 `--amd-igpu`）；NVIDIA RTX 2000-5000 |
| gzip 压缩 | 支持，可减少高达 80% 矿池流量 |
| 连接方式 | 仅 SSL（端口 8048），无 TCP 回退 |
| 后端自动检测 | 自动检测 CUDA / ROCm，一个二进制通吃 |
| Stats API | 支持 `--api-port` 导出 Prometheus 指标 |
| 算力参考 | 4090 ~254 TH/s，5090 ~335 TH/s，7900 XT ~41.4 TH/s（均低于 PeakMiner） |

### KRig 命令行示例

```bash
# 基本命令（页面官方格式）
./krig-miner --url stratum+ssl://prl.kryptex.network:8048 --user <wallet>

# 指定区域 + SOLO
./krig-miner \
  --url stratum+ssl://prl-hk.kryptex.network:8048 \
  --user solo:<wallet>/<worker>

# 指定 GPU
./krig-miner --url ... --user ... -d 0,1

# 启用 API 监控
./krig-miner --url ... --user ... --api-port 4058

# 列出可用 GPU
./krig-miner --list-devices
```

### KRig 主要参数速查

| 参数 | 说明 | 示例 |
|------|------|------|
| `-o, --url` | 矿池地址（仅支持 `stratum+ssl://`） | `--url stratum+ssl://prl-hk.kryptex.network:8048` |
| `-u, --user` | 钱包地址（SOLO 加 `solo:` 前缀） | `--user solo:prl1xxx.../worker` |
| `-p, --password` | 矿池密码 | `-p x` |
| `-d, --devices` | 指定 GPU 编号 | `-d 0,1` 或 `-d all` |
| `--devices-pci` | 按 PCI 地址选 GPU | `--devices-pci 0000:01:00.0` |
| `--no-cuda` / `--no-rocm` | 禁用 CUDA / ROCm 后端 | — |
| `--amd-igpu` | 启用 AMD 集成显卡（RDNA 3.5） | — |
| `--list-devices` | 列出检测到的所有 GPU | — |
| `--api-port` | Prometheus 指标端口 | `--api-port 4058` |

---

# 问题与解决

实现过程中遇到的坑以及对应解法，按日期先后顺序记录：

## 2026-08-11

### Docker 容器内矿池 DNS 解析超时
- **问题**：容器启动后日志持续报 `timed out connecting to prl-hk.kryptex.network:8048`，宿主机 TCP 测试该端口却可达
- **根因**：容器使用默认 DNS（宿主机 `/etc/resolv.conf`），解析部分 Kryptex 区域节点域名超时。宿主机能通是因为系统 DNS 配置不同
- **解决**：`docker run` 增加 `--dns 8.8.8.8 --dns 1.1.1.1` 指定外部 DNS；同时改用全球节点 `prl.kryptex.network` 替代区域节点 `prl-hk`
- **教训**：容器 DNS 和宿主机 DNS 行为可能不一致，挖矿场景建议显式指定可靠的公共 DNS

### PeakMiner `latest` 与固定版本实际相同
- **问题**：文档原推荐锁定 `peakminer/peakminer:2.9.0`，后改为 `latest`
- **验证**：实际运行时 `latest` 拉取到的也是 v2.9.0（build=20260811-d1c3a0），两者完全一致
- **结论**：使用 `latest` 即可，PeakMiner 更新频率低且 `latest` 指向的就是最新稳定版

### 4090 双卡算力验证
- **实测数据**（`latest` / v2.9.0，全球节点，无超频）：
  - GPU 0: 292.0 TH/s，76°C，448W，fan 82%，能效 651.9 GH/W
  - GPU 1: 286.8 TH/s，85°C，449W，fan 98%，能效 638.8 GH/W
  - 总算力: 578.9 TH/s，拒绝率 0%
- **结论**：与 PeakMiner 官方标称 291.2 TH/s 基本一致，偏差 < 1%。GPU 1 温度偏高（85°C），建议考虑通过 `--gpu-fan-target1` 或 `--gpu-power1` 调优

### PeakMiner API 绑定 127.0.0.1，bridge 模式 `-p` 端口映射无效
- **问题**：Docker bridge 模式下 `-p 4068:4068` 端口映射正常，但宿主机和 VS Code 均无法访问 `http://localhost:4068/summary`
- **根因**：PeakMiner 的 `--api-port` **硬编码绑定 `127.0.0.1`**（仅本地回环），不支持配置为 `0.0.0.0`。Docker bridge 模式虽然将宿主机流量转发到容器，但目标地址是容器内 `127.0.0.1`，外部连接无法命中 lo 接口
- **解决**：改用 `--network host` 模式。host 模式下 API 直接监听宿主机 `127.0.0.1:4068`，宿主机 `curl localhost:4068/summary` 和 VS Code 端口转发均可正常访问
- **教训**：挖矿软件 API 通常只考虑本机访问，不会监听 `0.0.0.0`。Docker 化部署时优先考虑 `--network host`

### `-u` 参数中钱包地址被误替换
- **问题**：文档中 SOLO 命令的 `-u` 值一度变成 `solo:https://github.com/peakminer/peakminer/agent`
- **根因**：从网页复制时混入了页面上的占位文本
- **解决**：修正为正确的 `solo:prl1pldsjzegmcujgsp5rlhslp4gyg6zvkcqq2czmpqrptezay0pcmd8sveydvl/agent`
- **教训**：网页生成的命令中占位符需逐项核对，不能直接照搬
