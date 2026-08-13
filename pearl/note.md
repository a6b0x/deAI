# Pearl (PRL) 双矿工对比笔记

同一钱包、同一矿池（prl.kryptex.network）、同为 PPS+，按 worker 分开统计：
- worker `peak` = PeakMiner，stratum+ssl 端口 8048
- worker `forge` = ForgeMiner，明文 stratum 端口 7048

硬件：2 × RTX 4090（450W 功耗墙）。

---

## 第一轮（2026-08-12 ~ 2026-08-13）：GPU 0 = PeakMiner，GPU 1 = ForgeMiner

### 矿池 24h 数据（截图 2026-08-13 10:53）
| Worker | Miner | 30min | 24h | Valid/Stale/Invalid |
|--------|-------|-------|-----|---------------------|
| peak | peakminer/2.9.0 | 290.23 TH/s | 290.54 TH/s | 2798 / 7 / 0 |
| forge | ForgeMiner/1.5.11 | 240.19 TH/s | 264.48 TH/s | 2565 / 0 / 0 |

### 排查结论
- **GPU 1 热降频**：`nvidia-smi` 降频标志 `0x20`（SW thermal），85°C / 2175MHz / 416W，
  对比 GPU 0：77°C / 2310MHz / 449W（标志 `0x04` = 功耗上限，正常）。
  → ForgeMiner 算力偏低主要源于卡的散热差异，而非软件本身。
- ForgeMiner 本机自报 24h 均值 272 TH/s > 矿池 264 TH/s，差值为断连空窗损失。
- 两台矿工均有间歇性断连：forge 多次 "disconnected; reconnecting in 5s"、
  "pool stopped answering share submits"；peakminer 有 pool idle timeout、
  TLS handshake eof（rustls unexpected EOF）。→ 总算力曲线毛刺的来源。
- peak 有 7 个 stale、forge 为 0；两者端口/协议不同（SSL 8048 vs 明文 7048），
  stale 差异可能来自端口而非软件。
- 矿池提示两款软件均已过时。

---

## 第二轮（2026-08-13 03:1x 起）：GPU 对调交叉验证

- PeakMiner → GPU 1，ForgeMiner → GPU 0（`docker-compose.yml` 已改 device_ids）。
- 第一轮日志归档：`logs/round1-gpu0-peak_gpu1-forge/{miner.log,forge.log}`。
- 镜像已升级：PeakMiner v2.9.0 → **v2.9.1**；ForgeMiner v1.5.11 → **v1.5.13**。

### 启动初始读数（仅数分钟，参考用）
| Miner | GPU | 算力 | 温度 |
|-------|-----|------|------|
| ForgeMiner v1.5.13 | GPU 0 | ~295 TH/s | 78°C |
| PeakMiner v2.9.1 | GPU 1 | ~266 TH/s | 86°C |

差距跟着卡走（约 ±8%），初步印证第一轮差距主要是散热/卡的体质差异。

### 待办
- [ ] 第二轮跑满 24h 后取矿池 24h 均值，两轮交叉平均得出真实软件效率差
- [ ] 关注 GPU 1 散热（85°C+、风扇 100%），长期热降频两张卡都吃亏
- [ ] 确认矿池"挖矿软件已过时"提示消除
