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

---

## 故障记录（2026-08-14）：ForgeMiner 断连 5h+

- **现象**：矿池后台 worker `forge` 最后活跃 2026-08-14 05:29:48（UTC），GPU 0 空转。
- **时间线**（日志 `logs/forge.log`，UTC）：
  - 08-13 21:29:48 最后一次 share accepted
  - 21:29:57 `disconnected (pool closed the connection)` → 重连 7048 后矿池要求切 TLS，
    但 `TLS connect failed: unexpected end of file`，自此死循环重试约 5 小时。
- **根因**：矿池明文端口 `prl.kryptex.network:7048` 已失效——openssl 验证 7048 的
  明文/TLS 均直接 EOF，而 8048 的 TLSv1.3 握手正常（PeakMiner 一直用它，未受影响）。
- **修复**：`docker-compose.yml` 中 forge 的 `--pool` 由 `prl.kryptex.network:7048`
  改为 `ssl://prl.kryptex.network:8048`，`docker compose up -d forgeminer` 重建后
  恢复（282 TH/s，share accepted 正常）。两矿工现同端口 8048，端口差异变量消除。
- **教训**：forge 对明文端口挂掉无自愈能力（TLS 握手 EOF 会无限重试），宜用多池
  failover 写法 `--pool ssl://...:8048,ssl://...:8048` 或加监控告警。

## 更新记录（2026-08-14）：ForgeMiner v1.5.13 → v1.5.15

- 矿池提示"挖矿软件已过时"，检查 Docker Hub 发现远程 `latest`（digest `a3912d8d`）
  于 08-14 00:19 UTC 推送，本地还是 26h 前旧版（digest `382eb68e`）。
- 升级流程（`latest` tag 无需删镜像）：
  1. `docker compose pull forgeminer` — 拉取新 latest
  2. `docker compose up -d forgeminer` — digest 变化自动重建容器
  3. 验证 `forge --version` = 1.5.15、share accepted 正常（274 TH/s）
  4. `docker image prune -f` — 清理旧版 dangling 镜像（回收 68MB）
- 注意：**不能先 `docker rmi hashraptor/forge:latest` 再重启**——运行中容器正引用
  该 tag 会被拒绝，强删 `-f` 会弄坏运行中的容器。正确顺序永远是 pull → up → prune。
