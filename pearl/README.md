# Pearl Miner 使用说明

## 目录结构

```
/root/deAI/peal
├── pearl          # 矿工管理脚本（主程序入口）
├── pearl-miner    # 挖矿二进制程序
├── miner.log      # 运行日志（自动生成）
├── miner.pid      # 进程 PID 文件（自动生成）
└── README.md      # 本文档
```

## 快速开始

```bash
cd /root/deAI
./pearl start
```

## 命令列表

| 命令 | 说明 |
|------|------|
| `./pearl start` | 启动矿工（后台运行，自动写入日志） |
| `./pearl stop` | 停止矿工（优雅关闭，超时强制终止） |
| `./pearl restart` | 重启矿工 |
| `./pearl status` | 查看运行状态、PID、运行时长、最近算力 |

## 启动前网络说明

- 当前矿池域名 `pool.pearlhash.xyz` 依赖你本机的 Clash 虚拟网卡/TUN 才能稳定解析。
- 现在脚本会在真正启动矿工前先检查矿池域名解析。
- 如果 Clash 没启动，或者虚拟网卡没打开，脚本会直接报错退出，而不是让矿工后台刷一堆 `0.00 H/s`。
- 如果刚打开 Clash，建议等待几秒再执行 `./pearl start`。

## 常用操作示例

### 1. 启动矿工
```bash
./pearl start
```
输出示例：
```
[INFO]  2026-07-29 10:00:00 检测到 GPU 数量: 2
[INFO]  2026-07-29 10:00:00 ========================================
[INFO]  2026-07-29 10:00:00 启动 Pearl Miner
[INFO]  2026-07-29 10:00:00 矿池:        pool.pearlhash.xyz:9000
[INFO]  2026-07-29 10:00:00 钱包地址:    prl1pldsjze...sveydvl
[INFO]  2026-07-29 10:00:00 工作者名称:  agent260721
[INFO]  2026-07-29 10:00:00 日志文件:    /root/deAI/miner.log
[INFO]  2026-07-29 10:00:00 ========================================
[INFO]  2026-07-29 10:00:01 矿工启动成功! PID: 12345
[INFO]  2026-07-29 10:00:01 查看日志: tail -f /root/deAI/miner.log
```

### 2. 查看运行状态
```bash
./pearl status
```
输出示例：
```
[INFO]  2026-07-29 10:05:00 矿工运行中 | PID: 12345 | 运行时长:  05:00
[INFO]  2026-07-29 10:05:00 最近算力: 510.23 TH/s
```

### 3. 停止矿工
```bash
./pearl stop
```

### 4. 重启矿工
```bash
./pearl restart
```

## 自定义配置

通过环境变量临时覆盖配置，无需修改脚本：

```bash
# 自定义工作者名称启动
WORKER_NAME=my-rig-01 ./pearl start

# 自定义矿池和钱包地址启动
POOL_HOST="pool.pearlhash.xyz:9000" \
USER_ADDRESS="你的钱包地址" \
WORKER_NAME="rig-02" \
./pearl start
```

## 日志管理

- **日志路径**: `/root/deAI/miner.log`
- **自动轮转**: 日志超过 50MB 时自动归档为 `miner.log.old`
- **实时查看日志**:
  ```bash
  tail -f /root/deAI/miner.log
  ```
- **查看最近 100 行日志**:
  ```bash
  tail -100 /root/deAI/miner.log
  ```
- **查看算力汇总**:
  ```bash
  grep "Hashrate Total" /root/deAI/miner.log | tail -20
  ```

## 脚本特性

1. **进程守护**: PID 文件追踪，避免重复启动
2. **优雅关闭**: 先 SIGTERM，10 秒超时后 SIGKILL
3. **前置检查**: 自动检测 GPU、二进制文件权限、矿池域名解析
4. **网络提示**: 无法解析矿池时，明确提示先打开 Clash 虚拟网卡/TUN
5. **日志轮转**: 防止日志文件无限增长
6. **启动分隔标记**: 每次启动前写入一条新的日志分隔线，便于区分旧日志
7. **灵活配置**: 环境变量覆盖，支持多实例差异化配置
8. **状态监控**: 一键查看运行时长和最近算力

## 故障排查

| 问题 | 排查方法 |
|------|---------|
| 启动失败 | 查看日志末尾: `tail -50 /root/deAI/miner.log` |
| 提示无法解析矿池域名 | 先打开 Clash 虚拟网卡/TUN，再执行 `./pearl start` |
| 算力异常 | 查看 GPU 状态: `nvidia-smi` |
| 进程无法停止 | 手动强制: `kill -9 $(cat /root/deAI/miner.pid)` |
| 重复实例 | 查看所有进程: `ps aux \| grep pearl-miner` |

## 开机自启（可选）

编辑 `/etc/rc.local`，在 `exit 0` 前添加：

```bash
cd /root/deAI && ./pearl start
```

或使用 systemd 服务（推荐）：

```ini
# /etc/systemd/system/pearl-miner.service
[Unit]
Description=Pearl Miner
After=network.target nvidia-persistenced.service

[Service]
Type=forking
WorkingDirectory=/root/deAI
ExecStart=/root/deAI/pearl start
ExecStop=/root/deAI/pearl stop
Restart=on-failure
RestartSec=10
User=root

[Install]
WantedBy=multi-user.target
```

启用服务：
```bash
systemctl daemon-reload
systemctl enable pearl-miner
systemctl start pearl-miner
```
