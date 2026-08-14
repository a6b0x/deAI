# GitHub 同步连接超时排查与修复记录

> 日期：2026-08-14
> 环境：Linux，Clash/Mihomo（mihomo-party）TUN 模式代理

## 一、现象

通过 VS Code 插件同步 `deAI` 仓库时执行 `git push deAI main:main` 报错：

```
fatal: unable to access 'https://github.com/a6b0x/deAI.git/':
Failed to connect to github.com port 443 after 132534 ms: Connection timed out
```

## 二、排查过程（诊断命令与证据）

### 1. 确认代理进程与端口

```bash
ps aux | grep -i mihomo          # mihomo-party 在运行
ss -tlnp | grep -E "7890|7891"   # mixed-port 7890 / socks 7891 在监听
```

### 2. 确认 DNS 解析到 fake-ip

```bash
getent hosts github.com   # → 198.18.0.40
```

mihomo 配置为 `dns: enhanced-mode: fake-ip`，`fake-ip-range: 198.18.0.1/16`，因此 `github.com` 被解析为 fake-ip `198.18.0.40`，属正常现象。

### 3. 确认 TUN 流量正常进入 mihomo

```bash
ip route get 198.18.0.40   # → via 198.18.0.2 dev Mihomo table 2022 （正确进入 TUN）
```

mihomo 核心日志证实流量已进入并完成规则匹配：

```
[TCP] 198.18.0.1:48874 --> github.com:443 match DomainKeyword(github) using XFLTD
```

**结论：TUN 模式工作正常，无需修复。**

### 4. 找到真正失败点 —— 节点线路超时

mihomo 日志（`~/.config/mihomo-party/logs/core-2026-08-14.log`）：

```
level=warning msg="[TCP] dial XFLTD (match DomainKeyword/github) 198.18.0.1:48874 --> github.com:443
error: 0af4430.cnrcz.cn:13005 connect error: context deadline exceeded"
```

对比同一时刻走 7890 代理端口的连接：

```
[TCP] 127.0.0.1:50196 --> github.com:443 match DomainKeyword(github) using XFLTD[🇸🇬 新加坡 05]
```

- TUN 流量分配到 **XFLTD 策略组**，组内选中节点需经中转 `0af4430.cnrcz.cn:13005`（对应组内倾向选择的"香港 04"），该节点连接超时。
- 代理端口流量同组但选到了"新加坡 05"，1 秒内连通。
- 两条路径共用同一 mihomo 与同一节点池，差异仅在节点选择。

## 三、根因

**mihomo 的 XFLTD 策略组首选节点（经 `0af4430.cnrcz.cn:13005` 中转）失效/超时**，导致经 TUN 的 github.com 连接无法完成 TCP 握手，git 等待 132 秒后报连接超时。属于节点线路不稳定，与 TUN 模式本身无关。

## 四、已执行的临时修复（有效）

给 git 全局配置走本地代理，绕开策略组选到的坏节点：

```bash
git config --global http.proxy  http://127.0.0.1:7890
git config --global https.proxy http://127.0.0.1:7890
```

验证：

```bash
git ls-remote deAI            # 成功返回远程 main 分支
timeout 60 git push deAI main:main   # 仍需认证（见下）
```

## 五、遗留问题

### 1. 认证

推送时提示：

```
fatal: could not read Username for 'https://github.com': No such device or address
```

排查：`~/.ssh` 无私钥、无 `credential.helper`、无 `.git-credentials`、无 token 环境变量。
方案：VS Code 内已有 GitHub 登录，可在 VS Code 插件内重试；或配置 PAT：

```bash
git config --global credential.helper store
# 首次 push 时输入用户名 + PAT（非密码）
```

### 2. 节点线路根治

- 在 mihomo-party 面板中为 XFLTD 组手动选择稳定节点（如日志验证可用的"新加坡 05"）。
- 给组内节点测速，剔除失效节点。
- 为策略组开启失败自动切换（fallback），避免死磕坏节点。

## 六、相关命令速查

```bash
# 查看代理进程
ps aux | grep -i mihomo

# 查看代理监听端口
ss -tlnp | grep -E "7890|7891"

# 验证 fake-ip 解析
getent hosts github.com

# 验证内核选路
ip route get 198.18.0.40

# 查看 mihomo 核心日志
tail -f ~/.config/mihomo-party/logs/core-$(date +%F).log

# 测试代理连通性
curl -x http://127.0.0.1:7890 -sI https://github.com -w "%{http_code}\n"
```
