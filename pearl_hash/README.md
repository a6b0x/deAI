# pearl_hash — Pearl 挖矿一键运维

基于 WildRig Multi，一条命令启动，崩溃自动重启，实时监控 GPU 状态。

## 三步开始挖矿

**第一步：改钱包地址**

编辑 `config/.env`，把 `USER_ADDRESS` 改成你自己的 Pearl 钱包：

```bash
vim config/.env
```

```ini
USER_ADDRESS="prl1你的钱包地址"
```

> 没有钱包？去 [pearlhash.xyz](https://pearlhash.xyz/#start-mining) 生成一个。

**第二步：下载矿工程序**

```bash
./pearl_hash -y update
```

**第三步：启动**

```bash
./pearl_hash start
```

看到 `已启动` 就行了。矿工会一直在后台运行，崩溃了自动重启。

---

## 日常使用

### 看看挖矿状态

```bash
./pearl_hash status       # 一次性快照
./pearl_hash monitor      # 实时面板，每 5 秒刷新（Ctrl+C 退出）
./pearl_hash monitor 3    # 每 3 秒刷新
```

显示总算力、每张 GPU 温度/风扇/功耗、accepted/rejected 数、矿池延迟。

### 看收益

浏览器打开 https://pearlhash.xyz/account/你的钱包地址

或者在 `./pearl_hash status` 输出最底部也有直达链接。

### 看日志

```bash
./pearl_hash logs        # 最近 50 行
./pearl_hash logs 200    # 最近 200 行
./pearl_hash logs -f     # 实时跟踪（Ctrl+C 退出）
```

### 停止挖矿

```bash
./pearl_hash stop
```

### 重启

```bash
./pearl_hash restart
```

---

## 特殊场景

### 跑 LLM 时需要释放 GPU

```bash
./pearl_hash pause       # 暂停挖矿，释放 GPU 算力
# 跑你的 LLM ...
./pearl_hash resume      # 恢复挖矿
```

### 临时换矿池区域（不改配置文件）

```bash
POOL_HOST=asia.pearlhash.xyz:9000 ./pearl_hash start
```

### 只用一张卡挖

```bash
GPU_DEVICES=0 ./pearl_hash start
```

### 更新矿工版本

```bash
./pearl_hash -y stop
./pearl_hash -y update
./pearl_hash start
```

旧版本会自动备份，不用担心。

### 接入 Prometheus 监控

```bash
# 加到 crontab，每分钟写一次指标
*/1 * * * * /root/deAI/pearl_hash/pearl_hash metrics > /var/lib/node_exporter/textfile_collector/pearl_hash.prom
```

---

## 所有命令一览

| 命令 | 干什么 |
|------|--------|
| `start` | 启动挖矿 |
| `stop [-y]` | 停止挖矿 |
| `restart` | 重启 |
| `status [--brief]` | 查看状态（一次性快照） |
| `monitor [秒]` | 实时监控面板（默认 5s 刷新） |
| `config` | 查看当前配置 |
| `logs [-f] [N]` | 查看日志 |
| `pause` | 暂停（释放 GPU） |
| `resume` | 恢复 |
| `pre_run_llm` | 暂停 + 提示跑完 LLM 后 resume |
| `metrics` | Prometheus 格式指标 |
| `version` | 版本信息 |
| `check-update` | 检查有没有新版本 |
| `update [-y]` | 下载安装新版本 |

---

## 配置说明

只需要关注 `config/.env` 里这几个：

| 配置项 | 说明 | 默认值 |
|--------|------|--------|
| `USER_ADDRESS` | 你的 PRL 钱包地址 | 示例地址（**必须改**） |
| `POOL_HOST` | 矿池地址 | `pool.pearlhash.xyz:9000` |
| `GPU_DEVICES` | 用哪几张卡，逗号分隔 | `0,1` |
| `MAX_GPU_TEMP` | 超过这个温度自动降速 | `85` °C |

其他配置保持默认就好，`.env` 里都有中文注释，需要调的时候再看。

修改配置后需要重启才生效：`./pearl_hash restart`

---

## 常见问题

**Q: 日志里看到 `Error UNKNOWN_ERROR when calling clGetPlatformIDs`**

正常。NVIDIA 用 CUDA，不需要 OpenCL，不影响挖矿。

**Q: rejected 比例很高**

大概率版本太老。rank-128 软分叉后旧版会大量拒绝。确保 ≥ 0.49.9：

```bash
./pearl_hash version
```

**Q: 怎么确认矿工在正常工作**

```bash
./pearl_hash logs 5
```

看到 `new job from pool.pearlhash.xyz:9000` 就说明连上矿池了。

---

## 环境要求

- Linux + NVIDIA 显卡 + 驱动
- `curl`、`python3`、`tar`、`gzip`
