# Discrete 挖矿 — 简易四步走

> 唯一主文档 (MINING-STEPS.md 已合并到这里)
>
> 官方参考:
> - 节点操作 https://docs.discrete.cash/#/operators/node-operation
> - 挖矿 https://docs.discrete.cash/#/operators/mining
> - 钱包 https://docs.discrete.cash/#/wallets/wallet-scope
> - Discrete v0.9.5 二进制 https://github.com/discretecoin/discrete/releases/tag/v.0.9.5

---

## 0. 总览 / 官方命令对照 / 硬件建议

### 0.1 官方命令 vs 本项目脚本

| 阶段 | 文档原命令 | 本项目脚本 |
|---|---|---|
| 准备 + 硬件扫描 | — (下载二进制) | [step1-prepare.sh](file:///root/deAI/discrete/scripts/step1-prepare.sh) |
| 启动空节点 (P2P+RPC) | `discreted --p2p-bind-ip 0.0.0.0 --p2p-bind-port 9330 --rpc-bind-ip 127.0.0.1 --rpc-bind-port 9331` | [step2-start-node.sh](file:///root/deAI/discrete/scripts/step2-start-node.sh) |
| 创建钱包 | `simplewallet --generate-new-wallet w.bin --daemon-address 127.0.0.1:9331` | [step3-create-wallet.sh](file:///root/deAI/discrete/scripts/step3-create-wallet.sh) |
| 启动 Headless 挖矿 | `discreted --mining-wallet /x --mining-password-file /p --mining-threads N --no-console` | [step4-start-mining.sh](file:///root/deAI/discrete/scripts/step4-start-mining.sh) |
| 状态检查 (进程/线程/端口/RPC/钱包) | — (组合命令) | [check.sh](file:///root/deAI/discrete/scripts/check.sh) |
| 优雅停止 | `kill -TERM <pid>` | [stop.sh](file:///root/deAI/discrete/scripts/stop.sh) |

### 0.2 硬件 & 线程建议 (step1 会自动打印)

Discrete 的 PoW 是 **DiscretePower = 1 次 ML-DSA-65 后量子签名 + 1 次 yespower-discrete**，都是**整数重算力**，CPU 超线程 (SMT/HT) 收益通常只有 **+5~15%**，但温度和功耗显著上升。

**step1 自动扫描后给出 3 档：**
| 档位 | 线程数 | 适用场景 |
|---|---|---|
| 🟡 保守 | 物理核 − 4 | 机器还跑 Docker / AI 服务 / 桌面应用 |
| 🟢 推荐 | **物理核数** | ✅ 性价比最高；step4 不传参数就默认用这个 |
| 🔴 激进 | 物理核 + 50%SMT (≤ 逻辑核) | 完全空机 + 散热良好；收益增量有限 |

手动覆盖示例 (直接在 step4 传参):
```bash
bash scripts/step4-start-mining.sh 16   # 固定 16 线程
```

---

## Step 1: 准备环境 + 硬件扫描

**目的**: 创建必需目录, 检查二进制, 自动扫硬件给出线程档位建议。

**执行**:
```bash
cd /root/deAI/discrete
chmod +x scripts/*.sh
bash scripts/step1-prepare.sh
```

**预期结果末尾示例** (会根据你的真实硬件变化):
```
CPU:              AMD EPYC 7302 16-Core Processor
  物理核总数:     16   (推荐挖矿线程上限)
  逻辑核(SMT):    32
内存总容量:       125 GB    (每线程 ~16MB, 内存不是瓶颈)
──────────────────── 挖矿线程档位建议 ────────────────────
  🟡 保守档:  12 线程   (= 物理核 - 4)
  🟢 推荐档:  16 线程   (= 物理核数)     ✅ 性价比最高
  🔴 激进档:  24 线程   (= 物理核 + SMT)
```

**失败处理**: bin/ 为空 → 从 [v0.9.5 release](https://github.com/discretecoin/discrete/releases/tag/v.0.9.5) 下载 `discrete-cli-linux-universal-v.0.9.5.tar.gz`, 解压把 `discreted` / `simplewallet` 放进 `bin/` 即可。

---

## Step 2: 启动空节点 (仅同步, 不挖矿)

**目的**: 启动 P2P + RPC, 同步区块链; simplewallet 创建钱包时必须能连上 127.0.0.1:9331。

**执行**:
```bash
bash scripts/step2-start-node.sh
```

**预期结果**: 看到 `0.0.0.0:9330` 和 `127.0.0.1:9331` 两个端口 LISTEN。
运行 `bash scripts/check.sh` 验证；RPC 段 `状态 status: OK` + `对端 peer ≥ 1` 就算通过。

---

## Step 3: ⚠️ 创建挖矿钱包 (交互式必做)

**目的**: 生成 PQ 身份钱包 (DiscretePower 必须绑定矿工的 PQ spend key，不能用裸地址挖矿)。

**前置检查**: step2 的 `127.0.0.1:9331` 必须已监听 (check.sh 里看得到)。

**执行**:
```bash
bash scripts/step3-create-wallet.sh
```

### 进入交互界面后固定 3 步:

1. **两次输入密码** (屏幕不显示)。然后另开终端马上写密码文件:
```bash
echo -n '你刚才设置的密码' > wallet/miner-password.txt
chmod 600 wallet/miner-password.txt
```

2. 到 `simplewallet>` 提示符后依次敲 3 条命令:
```
simplewallet> print_seed
# 👉 把输出的 seed 短语(24~25 个英文词)抄到离线位置
# 或直接落盘:
simplewallet> print_seed > /root/deAI/discrete/wallet/miner-seed.txt

simplewallet> address
# 👉 记下你的 PQ 钱包地址 (disc1q...)

simplewallet> exit
```

**完成后 `ls -la wallet/` 应看到**:
| 文件 | 备份优先级 |
|---|---|
| `miner.wallet` | ⚠️ 最好备份 (v0.9.5 含 keys) |
| `miner-password.txt` | ✅ 必需 |
| `miner-seed.txt` | ✅✅✅ **最重要，离线** (唯一恢复凭证) |
| `miner.wallet.address` | 非必需, 纯缓存 |

> 🔁 **钱包丢失 / 密码忘记时, 用 seed 恢复** (只在 seed phrase 还在时):
> ```bash
> # 方法 A: 有 seed 文件
> bin/simplewallet \
>   --restore-deterministic-wallet \
>   --mnemonic-file wallet/miner-seed.txt \
>   --generate-new-wallet wallet/miner.wallet \
>   --daemon-address 127.0.0.1:9331
>
> # 方法 B: 没 seed 文件, 手动逐词输入
> bin/simplewallet \
>   --restore-deterministic-wallet \
>   --generate-new-wallet wallet/miner.wallet \
>   --daemon-address 127.0.0.1:9331
> ```

---

## Step 4: 停止空节点 → 启动 Headless 挖矿

**官方 Headless 方式 (推荐)**: https://docs.discrete.cash/#/operators/mining?id=headless-daemon

**执行** (不传参数 → 默认用 step1 算出来的"推荐档=物理核数"; 传参则覆盖):
```bash
# 推荐: 自动选物理核数
bash scripts/stop.sh                       # 停掉 step2 的空节点
bash scripts/step4-start-mining.sh

# 或固定线程数:
bash scripts/step4-start-mining.sh 16
```

**脚本会做 3 件事**: ① 停旧进程 (SIGTERM→等30s→SIGKILL) ② 检查 `wallet/miner-password.txt` 是否存在 ③ `nohup` 启动带 `--mining-wallet --mining-password-file --mining-threads --no-console` 的 daemon。

**启动后立即验证**:
```bash
bash scripts/check.sh
```
看到 `CPU≥90% 的线程数 ≈ 你设定的 N` + 端口都 LISTEN + RPC 有返回 height/peer 就算 OK。

---

## 附录 A: 状态 / 日志 / 监控 FAQ

### A.1 「tail -f logs/discreted.log 没新东西, 是挂了吗?」
**正常。** Discrete 的 `--log-level 2` (INFO) 只在**事件触发时打日志**: 启动/停止/出块/连断peer/新区块到来/报错。挖矿稳定 + 没出块 + 网络稳定 = 长时间安静。

**看真实状态请用**:
```bash
bash scripts/check.sh   # 进程 / 线程 / 端口 / RPC height-difficulty-peer / 钱包 / data
```

### A.2 「Grafana CPU 显示 27.7% 合理吗? 16 线程应该 50% 啊!」
**合理，是归一化口径不一样。** 服务器 CPU 百分比有两种基准, 数值相差最多 32 倍 (nproc=32):

| 工具/面板 | 0%~100% 对应什么 | 32 核上 16 满线程的显示 |
|---|---|---|
| Grafana `node_cpu` 面板 / `vmstat` / `top` 总体 `%Cpu(s)` | **每核平均** → 「整机 0~100%」, 32 核满=100% | ~50% (快照会跳, 27%~60% 都正常) |
| `ps %CPU` / `top` 单进程列 (按 `H` 展开线程) | **每逻辑核 0~100%**, 32 核满=**3200%** | ~1600% (16 核 × 100%) |

**换算公式**:
```
实际占了多少"核等效算力" = nproc × Grafana显示%
例:  32 × 27.7% ≈ 8.9 核     (瞬时快照)
     32 × 66%   ≈ 21.1 核    (vmstat 3s 均值, 与 20 线程满吻合)
```
**怎么判断对不对**: 看 `check.sh` 里那句 `CPU≥90% 的线程数 = N` —— **这个数字等于你传的 `--mining-threads` 就对了**，跟 Grafana 的瞬时百分比没关系。

---

## 附录 B: 网络端口 & 防火墙

| 端口 | 默认绑定 | 说明 | 公网暴露? |
|---|---|---|---|
| TCP 9330 | 0.0.0.0 | P2P 对等节点通信 | ✅ 可以 (越多越好, 同步越快) |
| TCP 9331 | 127.0.0.1 | HTTP JSON-RPC | ❌ **绝对不要** (含 start_mining / save / exit 等管理方法) |
| TCP 9332 | 默认关 | HTTPS JSON-RPC | ⚠️ 配证书 + rpc-user/rpc-password 后谨慎 |

**ufw 参考 (只开 P2P 入站)**:
```bash
sudo ufw allow 9330/tcp comment 'Discrete P2P'
sudo ufw reload
sudo ufw status
```

NAT/路由器映射不同公网端口 → 启动时加: `--p2p-external-port <PORT>`

---

## 附录 C: 生产部署: systemd (可选)

长期服务器运行建议用 systemd 管。文件在:
- 纯节点: [discrete-node.service](file:///root/deAI/discrete/systemd/discrete-node.service)
- 挖矿节点: [discrete-miner.service](file:///root/deAI/discrete/systemd/discrete-miner.service)

```bash
sudo useradd -r -s /usr/sbin/nologin discrete
sudo chown -R discrete:discrete /root/deAI/discrete/data /root/deAI/discrete/logs /root/deAI/discrete/run /root/deAI/discrete/wallet
sudo cp systemd/discrete-miner.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now discrete-miner
sudo systemctl status discrete-miner
journalctl -u discrete-miner -f
```

---

## 附录 D: 常见问题 Troubleshooting

| 症状 | 排查 / 解决 |
|---|---|
| 没有 peer / 0 连接 / 不同步 | check.sh 里看 `出=0 入=0` → 检查 9330 出方向防火墙；或启动加 `--add-seed-node seed.example.org:9330` |
| Mining 不开始 / 报 wallet 错误 | 检查 `wallet/miner-password.txt` 内容与创建时密码一致；`bin/simplewallet --wallet-file wallet/miner.wallet --password "$(cat wallet/miner-password.txt)" --daemon-address 127.0.0.1:9331 --command balance` 能打开就不是密码问题 |
| 出块但钱包 balance 没变化 | 等 coinbase maturity 到期 (协议规定, 几十块)；再跑 `balance` |
| CPU 温度过高 / 功耗大 | 减线程: `bash scripts/stop.sh && bash scripts/step4-start-mining.sh 12` |
| 数据库损坏 / 非正常断电后启动报 LMDB | 备份 `data/*.lmdb` 后, 删除 `data/` 下除 `*.lmdb` 外的临时文件; 或整体删 `data/` 重同步 (不影响钱包, 钱包在 wallet/) |
| Finality Fork 警告 | getinfo 里 `finality_fork_warning: true` → 等待官方节点 catch up，不要转账或信任未 finalize 的块 |

---

## 附录 E: 安全清单 (生产前必过)

- [ ] `wallet/miner-seed.txt` 的内容已经复制到**离线**介质 (纸/加密U盘/密码管理器)
- [ ] `wallet/miner-password.txt` 和 `wallet/miner.wallet*` 都是 `chmod 600`
- [ ] 9331 RPC 只绑定 `127.0.0.1`，防火墙上没放行 9331/9332 入站
- [ ] 若跑 systemd，使用非 root 用户 (`discrete`) 运行
- [ ] 线程数从保守开始，观察 30 分钟温度/功耗再往上加

---

## 附录 F: 目录结构

```
/root/deAI/discrete/
├── STEPS.md                      ← 你正在看的主文档
├── MINING-STEPS.md               ← 跳转说明, 所有内容已合并到 STEPS.md
├── bin/                          ← discreted + simplewallet 二进制
├── scripts/                      ← 6 个可执行脚本 (step1~4 + check + stop)
├── systemd/                      ← 可选 systemd 服务文件
├── config/                       ← Discrete.conf 参考模板 (脚本不传 --config-file, 仅参考)
├── data/                         ← 区块链 LMDB 数据 (目录大)
├── wallet/                       ← miner.wallet / password / seed (请备份!)
├── logs/                         ← discreted.log (事件型日志)
├── run/                          ← discreted.pid
├── downloads/                    ← 下载缓存
└── scripts.old/                  ← 早期复杂脚本备份, 可忽略
```
