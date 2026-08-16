# 主机安全分析报告（公开版）

> 本版本已脱敏：所有 IP 地址、公钥指纹、设备名、钱包地址均替换为占位符。
> 内部完整版请另行保存，勿提交至公开仓库。

- 基线分析：2026-08-06
- 实测复验：2026-08-14（数据均为当日实机执行命令所得）
- 分析对象：Ubuntu 22.04.5 LTS 主机（内核 6.8.0-136-generic）
- 分析身份：root

---

## 一、分析框架

采用「资产 → 暴露面 → 威胁 → 脆弱性 → 风险 → 处置」六层框架，对应 PDR（防护-检测-响应）模型：

| 层级 | 分析目标 | 关键问题 |
|------|---------|---------|
| 1. 资产识别 | 明确保护对象 | 系统上运行了什么？哪些是业务必需？ |
| 2. 暴露面分析 | 攻击者可触达的入口 | 哪些端口/服务对公网开放？ |
| 3. 威胁检测 | 已发生/正在发生的攻击 | 有无入侵痕迹、暴力破解、可疑进程？ |
| 4. 脆弱性评估 | 防护体系的薄弱环节 | 认证、防火墙、权限配置是否加固？ |
| 5. 风险定级 | 威胁 × 脆弱性 × 资产价值 | 哪些问题必须立即处理？ |
| 6. 处置建议 | 消除风险、建立长效机制 | 短期止血 + 长期加固方案 |

---

## 二、分析步骤与实测发现（2026-08-14）

### 步骤 1：资产识别

**执行**：`ps aux --sort=-%cpu`、`docker ps`

**发现**：
- 有效用户：root、user（uid 1000）
- Docker 业务容器：gitea、registry(-ui)、grafana、prometheus、cadvisor、dcgm-exporter、node-exporter、solar-server
- 挖矿负载（形态已变化，详见步骤 3）：宿主机 `peakminer` + 容器 `kryptex-prl-forgeminer` / `kryptex-prl-peakminer`
- 远程控制：awesun（向日葵）、rustdesk 仍在运行，rustdesk 仍由 root 经 sudo 以 gdm 用户启动
- 新增：mihomo/mihomo-party 代理软件运行（仅监听 127.0.0.1:7890-7892，暴露面可控）

### 步骤 2：暴露面分析

**执行**：`ss -tlnp`、`docker ps --format "{{.Names}}\t{{.Ports}}"`

**全网（0.0.0.0/*）监听实测清单**：

| 端口 | 归属 | 对比 08-06 基线 |
|------|------|----------------|
| 22 | sshd | 未变，仍全接口 |
| 2222 | gitea（SSH） | 未变 |
| 3389 | xrdp | 未变，仍全网 |
| 3000 / 3100 | grafana / gitea web | 未变 |
| 5000 / 5100 | registry / registry-ui | 未变 |
| 8082 / 9090 / 9400 | cadvisor / prometheus / dcgm | 未变 |
| 5901 | solar-server | **新增暴露** |
| 19091 | agent-tool-host（IDE 组件） | **新增暴露** |

**小结**：公网可触达入口增至 12 个，较基线新增 5901、19091 两个，暴露面未收敛反而扩大。其中 19091 为 IDE 组件监听全网，属配置疏漏（IDE 远程服务正常应仅监听 127.0.0.1）。

### 步骤 3：威胁检测

**执行**：`zgrep "Failed password\|Invalid user" /var/log/auth.log*`、`zgrep "Accepted" /var/log/auth.log*`、`pgrep -af pearl`

**攻击活动实测统计（来源 IP × 失败次数）**：

| 来源（占位） | 失败次数 | 活动时间 | 说明 |
|---------|---------|---------|------|
| `<攻击源A>`（境外） | 7337 | 08-05 止，此后无活动 | 与基线一致，已停止 |
| `<攻击源B>`（境外，同网段） | 264 | **08-10 ~ 08-13 仍在进行，且直接爆破 root 密码** | **新增攻击源，攻击持续中** |
| 内网误操作来源 | 各数次 | — | 数量级为个位数 |

**成功登录实测统计（`Accepted`，root，按次数排序）**：

| 来源（占位） | 次数 | 性质 |
|---------|------|------|
| `<管理源A>` | 182（基线 73） | 主要管理源，频次持续增长 |
| `<管理源B>` | 43（基线 34） | 管理源，待确认 |
| `<新增源C>` | 40（基线 0） | **新增公网源，高频登录 root，含凌晨时段** |
| `<新增源D>` | 22（基线 0） | **新增公网源，待确认** |
| `<新增源E>` | 11（基线 0） | **新增公网源，待确认** |
| `<装机源F>` | 17 | 含装机日密码登录引导行为（见下） |
| `<偶发源G>` | 1 | 偶发，待确认 |
| 内网来源 | 数次 | 正常 |

**小结**：公网 root 成功登录来源由基线的 2~3 个增至 **7 个**。各 IP 与登录设备的对应关系已通过密钥指纹完成绑定（见下表）。

**登录源 ↔ 设备对应关系（基于密钥指纹绑定，08-14 实测）**：

| 来源（占位） | 认证方式 | 使用密钥 | 登录设备 | 判定 |
|---------|---------|---------|---------|------|
| `<管理源A>` | publickey ×182 | `<指纹A>` ×182 | **设备A** | 本人（待复核） |
| `<管理源B>` | publickey ×43 | `<指纹A>` ×23、`<指纹B>` ×20 | **设备A + 设备B** | 本人（待复核） |
| `<新增源C>` | publickey ×40 | `<指纹A>` ×19、`<指纹B>` ×21 | **设备A + 设备B** | 本人（待复核） |
| `<新增源D>` | publickey ×22 | `<指纹A>` ×22 | **设备A** | 本人（待复核） |
| `<新增源E>` | publickey ×11 | `<指纹A>` ×11 | **设备A** | 本人（待复核） |
| `<装机源F>` | publickey ×12 + password ×5 | `<指纹A>` ×11、`<指纹B>` ×1 | **设备A + 设备B** | 本人（待复核）；密码登录为装机日引导 |
| `<偶发源G>` | publickey ×1 | `<指纹A>` ×1 | **设备A** | 本人（待复核） |

**密钥指纹 ↔ 设备映射（`ssh-keygen -lf` 实测）**：

| 密钥指纹 | 注释（设备） | 部署位置 | 日志使用次数 |
|---------|-------------|---------|-------------|
| `<指纹A>` | 设备A（MacBook） | root + user 的 authorized_keys | 323 |
| `<指纹B>` | 设备B（MacBook） | 仅 root 的 authorized_keys（装机日写入） | 42 |

**验证逻辑（如何判定"本人登录"还是"被攻击"）**：

1. **认证方式分流**：爆破攻击在日志中表现为海量 `Failed password`（本机 7600+ 次，全部失败）；而全部 `Accepted` 中 360 次为 publickey、仅 5 次为 password。攻击者无法伪造 publickey 认证成功——必须持有对应私钥。
2. **指纹绑定**：日志中每条 `Accepted publickey` 记录携带 `SHA256:` 指纹（sshd 默认 INFO 级别即记录）。将全部登录指纹与 `ssh-keygen -lf authorized_keys` 的本地公钥指纹比对：**365 次公钥登录只出现 2 个指纹，且与 authorized_keys 中两把密钥完全吻合，无第三方未知指纹**。若曾出现未知指纹，则说明攻击者写入了新公钥，属实锤入侵。
3. **行为佐证**：5 次密码登录全部集中在装机日 19:45~19:53，与 root authorized_keys 写入时间（19:50）交错吻合，符合 `ssh-copy-id` 引导流程（先密码登录、再写入公钥、之后转密钥登录），且来源与后续密钥登录为同一 IP，判定为管理员本人装机操作。
4. **剩余人工确认项**：指纹注释指向设备A、设备B 两台 Mac。在两台设备上执行 `ssh-keygen -lf ~/.ssh/id_rsa.pub` 复核指纹，**两台均为本人持有 → 全部登录记录确认为本人行为**；任一不认识 → 私钥已泄露，立即按入侵事件响应（清除公钥、轮换密钥、取证）。

**结论**：7 个公网 IP 不是 7 个攻击者，而是两台 Mac 经不同网络出口（家庭宽带、移动网络）登录产生的。攻击与登录是两条独立的线：攻击（境外网段）全部失败，登录全部经由本人密钥。

**可疑进程实测**：
- 08-06 报告的 `/root/deAI/pearl/pearl-miner`（连 pearlhash 矿池）**已不存在**
- 当前挖矿负载变为：
  - 宿主机：`/opt/peakminer/peakminer`，连接 kryptex 矿池，已运行 21 天
  - 容器：`kryptex-prl-peakminer`、`kryptex-prl-forgeminer`
  - `/root/deAI/pearl/` 目录仍在，内有 docker-compose.yml（近期有修改记录）
- 部署形态从单进程升级为「宿主机 + 容器 + compose 编排」，指向**人为持续运维**而非一次性植入，但仍需负责人书面确认为授权行为

### 步骤 4：脆弱性评估

**执行**：`iptables -L INPUT -n`、`ufw status`、`systemctl is-active fail2ban`、`grep ... /etc/ssh/sshd_config`、`ls /etc/ssh/sshd_config.d/`

**实测结果（08-06 报告的全部短期止血项均未落实）**：

| 检查项 | 实测状态 | 判定 |
|--------|---------|------|
| iptables INPUT | policy ACCEPT，**零规则** | 高危，未整改 |
| ufw | inactive | 高危，未整改 |
| fail2ban | inactive（已安装未启用） | 高危，未整改 |
| PermitRootLogin | 未配置（默认允许） | 高危，未整改 |
| PasswordAuthentication | 未配置（默认允许） | 高危，未整改 |
| sshd_config.d/ | 目录为空 | 无任何加固覆盖 |

**authorized_keys 实测**：
- root：含两把密钥（设备A、设备B），设备B 密钥为装机日新增
- user：仅设备A 密钥
- root 新增密钥时间点（装机日）与系统启动日吻合，需确认设备B 归属

**计划任务实测**：root crontab 为空；/etc/cron.d/ 仅系统默认项（anacron、e2scrub_all），无异常。

### 步骤 5：风险定级（实测更新）

| 编号 | 风险项 | 实测威胁证据 | 实测脆弱性 | 风险等级 | 趋势 |
|------|--------|-------------|-----------|---------|------|
| R1 | SSH 爆破成功 | 新增境外攻击源仍在爆破 root | 密码认证开、无 fail2ban、零防火墙规则 | **严重** | ↑ 攻击持续 |
| R2 | 不明来源 root 登录 | 公网成功登录源增至 7 个（已指纹验证为本人设备，待复核） | PermitRootLogin 默认允许 | **高** | → 已基本澄清 |
| R3 | 挖矿负载 | 形态升级为宿主机+容器编排，连 kryptex 矿池 | 归属未书面确认 | 中（疑似自部署） | → 形态变化 |
| R4 | 暴露面扩大 | 新增 5901、19091 全网监听 | 无防火墙 | **高** | ↑ 端口增加 |
| R5 | RDP/远控暴露 | 3389 仍全网，双远控并存 | 无来源限制 | 中 | → 未整改 |

---

## 三、结论

1. **08-06 报告的短期止血项 8 天内零落实**：防火墙、fail2ban、SSH 加固全部未执行，主机仍裸奔于公网，且新增境外攻击源于昨日仍在爆破 root。
2. **威胁态势较基线恶化**：暴露端口 +2（5901、19091），攻击者已切换到 root 密码直爆。若不整改，失陷概率持续累积。
3. **登录源归属已实测验证**：全部公网登录仅使用 authorized_keys 中的两把已知密钥（对应两台本人设备），无第三方未知指纹；唯一密码登录为装机日 ssh-copy-id 引导行为。**结论：只要两台设备均为本人持有，登录记录即可确认为本人行为**；若任一设备不属本人，则说明私钥已泄露，须按入侵事件响应。
4. **挖矿负载指向自部署**：compose 编排 + 近期人工修改记录 + 统一钱包管理，属运维行为的可能性大，但需书面确认并纳入资产管理，而非默认放行。
5. **19091 端口（IDE 组件）全网监听属典型配置疏漏**，应立即收敛到 127.0.0.1。

---

## 四、处置方案

### 阶段一：立即执行（今日，约 30 分钟）

> **前置保护**：执行前先开一个 root SSH 会话保持不断，所有变更验证通过后再退出，防止防火墙/SSH 配置失误导致自我锁定。

#### 方案 1：复核两台 Mac 私钥指纹（5 分钟，无风险）

```bash
# 在两台设备上分别执行，与公开版中的占位指纹比对（内部版对照完整指纹）：
ssh-keygen -lf ~/.ssh/id_rsa.pub
```

- **两台都匹配** → 登录源确认闭环，无需进一步动作
- **任一不匹配/设备不认识** → 私钥泄露，立即：从 authorized_keys 删除对应公钥 → 全部密钥轮换 → 按入侵事件取证

#### 方案 2：启用 fail2ban（5 分钟，无风险）

```bash
cat > /etc/fail2ban/jail.local <<'EOF'
[sshd]
enabled = true
port = 22
maxretry = 3
findtime = 600
bantime = 3600
EOF
systemctl enable --now fail2ban
fail2ban-client status sshd   # 验证：应显示 jail 生效
```

- **效果**：爆破源 3 次失败即封禁 1 小时
- **回退**：`systemctl stop fail2ban` 即可，不影响正常登录
- **替代方案**：关闭密码认证（一劳永逸）、pam_faillock（系统级锁定）、sshguard/CrowdSec（封禁类）、端口敲门/VPN 单入口（彻底收敛）等，详见内部版附录

#### 方案 3：启用防火墙（10 分钟，**有误锁风险，严格按顺序执行**）

```bash
# 1. 先放通可信来源（按实际管理 IP/网段替换 <管理IP段>）
ufw allow from <管理IP段A> to any port 22 proto tcp comment 'admin-a'
ufw allow from <管理IP段B> to any port 22 proto tcp comment 'admin-b'
ufw allow from 10.0.0.0/8; ufw allow from 172.16.0.0/12; ufw allow from 192.168.0.0/16

# 2. 放通业务必需端口（按需删减）
ufw allow 3100/tcp comment 'gitea-web'; ufw allow 2222/tcp comment 'gitea-ssh'
ufw allow 3000/tcp comment 'grafana'

# 3. 不放通 3389（xrdp 走内网或 VPN）

# 4. 最后启用（默认拒绝入站）
ufw default deny incoming; ufw default allow outgoing
ufw enable

# 5. 立即用新会话验证 SSH 可连，验证通过再关闭旧会话
```

- **回退**：若新会话连不上，用保持的旧会话执行 `ufw disable` 恢复
- **注意**：Docker 默认会绕过 ufw（直接写 iptables DOCKER-USER 链），容器端口需配合方案 7 收敛

#### 方案 4：收敛 19091 端口（5 分钟）

```bash
# agent-tool-host 为 IDE 远程组件，正常只需本地回环
# 定位配置：grep -r "19091\|0.0.0.0" <IDE服务目录>
# 将其监听改为 127.0.0.1 后重启对应服务；若无法配置，用防火墙兜底：
ufw deny 19091/tcp comment 'ide-agent-local-only'
```

### 阶段二：一周内

#### 方案 5：SSH 加固（10 分钟，**先确认密钥可登录再执行**）

```bash
# 确认：保持至少一个密钥登录会话在线！
cat > /etc/ssh/sshd_config.d/99-hardening.conf <<'EOF'
PermitRootLogin prohibit-password
PasswordAuthentication no
PubkeyAuthentication yes
MaxAuthTries 3
LoginGraceTime 30
EOF
sshd -t                      # 语法校验，必须无输出
systemctl reload sshd
# 用新会话分别验证：root 密钥可登录、密码登录被拒绝
```

- `PermitRootLogin prohibit-password`（而非 `no`）：保留 root 密钥登录能力，避免现有运维脚本中断；稳定后可改 `no`
- **回退**：删除 99-hardening.conf → `systemctl reload sshd`

#### 方案 6：挖矿资产确认与纳管（30 分钟）

```bash
# 1. 固定证据
docker inspect kryptex-prl-peakminer kryptex-prl-forgeminer > /root/deAI/infra/safe/miner-containers-$(date +%F).txt
ps -p $(pgrep -f peakminer) -o pid,lstart,cmd >> /root/deAI/infra/safe/miner-containers-$(date +%F).txt
# 2. 书面确认：钱包收益归属人、部署审批记录
# 3. 若确认为授权：写入资产清单 /root/deAI/infra/safe/inventory.md（用途/负责人/矿池）
# 4. 若无法确认：docker stop 相关容器 && kill <peakminer_pid>，并审计植入路径
```

#### 方案 7：收敛容器端口暴露（1~2 小时，逐项验证业务）

Docker 发布端口会绕过 ufw，需从 compose 层收敛：

```yaml
# 修改各服务 docker-compose.yml 的 ports，将 0.0.0.0 绑定改为内网/回环：
# 监控栈仅内网访问：
ports: ["<内网IP>:9090:9090"]   # prometheus
ports: ["<内网IP>:3000:3000"]   # grafana
ports: ["<内网IP>:5000:5000"]   # registry
# gitea SSH 若仅管理员使用，绑内网 + ufw 白名单；web 3100 保留公网则加反向代理认证
```

逐项 `docker compose up -d` 后验证业务可达性。优先级：registry 5000/5100（镜像仓库不应公网）> 监控栈 > 5901。

#### 方案 8：远控收敛（30 分钟）

- 二选一：保留向日葵则 `systemctl disable --now rustdesk` + `apt purge rustdesk`；保留 RustDesk 反之
- 留存者：开启二次验证/强密码，关闭无人值守免确认模式

### 阶段三：长期机制

#### 方案 9：新 IP 登录告警（20 分钟）

```bash
cat > /usr/local/bin/ssh-login-alert.sh <<'EOF'
#!/bin/bash
# 由 pam_exec 触发，新 IP 登录时告警
[ "$PAM_TYPE" = "open_session" ] || exit 0
IP=$(echo "$PAM_RHOST")
WHITELIST="10. 172.16. 172.17. 192.168. <管理IP段A> <管理IP段B>"
echo "$WHITELIST" | grep -q "$IP" && exit 0
MSG="[SSH告警] 新来源登录: user=$PAM_USER ip=$IP time=$(date '+%F %T') host=$(hostname)"
# 择一：webhook（钉钉/企微/飞书）或邮件
curl -s -X POST "https://oapi.dingtalk.com/robot/send?access_token=<TOKEN>" \
  -H 'Content-Type: application/json' \
  -d "{\"msgtype\":\"text\",\"text\":{\"content\":\"$MSG\"}}"
EOF
chmod +x /usr/local/bin/ssh-login-alert.sh
echo "session optional pam_exec.so /usr/local/bin/ssh-login-alert.sh" >> /etc/pam.d/sshd
```

#### 方案 10：每周基线比对（15 分钟）

```bash
cat > /usr/local/bin/weekly-baseline.sh <<'EOF'
#!/bin/bash
DIR=/root/deAI/infra/safe/baseline; mkdir -p $DIR
DATE=$(date +%F)
{ ss -tlnp; echo '---'; cat /root/.ssh/authorized_keys /home/user/.ssh/authorized_keys
  echo '---'; crontab -l; ls /etc/cron.d/
  echo '---'; find / -perm -4000 -type f 2>/dev/null
} > $DIR/$DATE.txt
PREV=$(ls $DIR/*.txt | grep -v $DATE | tail -1)
[ -n "$PREV" ] && diff $PREV $DIR/$DATE.txt | mail -s "baseline-diff $DATE" root || true
EOF
chmod +x /usr/local/bin/weekly-baseline.sh
echo '0 8 * * 1 root /usr/local/bin/weekly-baseline.sh' > /etc/cron.d/weekly-baseline
# 首次先手动执行一次建立基线：/usr/local/bin/weekly-baseline.sh
```

#### 方案 11：日志远程留存（20 分钟）

```bash
# 安装 rsyslog 转发到另一台可信主机（或日志服务）
apt install -y rsyslog
echo '*.* @@<日志服务器IP>:514' >> /etc/rsyslog.conf
systemctl restart rsyslog
# 至少保证 auth.log 实时外发，本机被清痕后仍有副本
```

### 执行顺序与依赖

```
今日：方案1(指纹复核) → 方案2(fail2ban) → 方案3(防火墙) → 方案4(19091)
       └ 方案1若不通过 → 转入侵响应流程，暂停其余变更
本周：方案5(SSH加固，依赖方案1通过) → 方案7(端口收敛) → 方案6(挖矿确认) → 方案8(远控)
长期：方案9(告警) → 方案10(基线) → 方案11(日志外发)
```

---

## 附：实测命令清单（可复用）

```bash
ss -tlnp                                                  # 监听端口及归属进程
docker ps --format "{{.Names}}\t{{.Ports}}"               # 容器端口映射
zgrep -h "Failed password\|Invalid user" /var/log/auth.log* | grep -oE 'from [0-9.]+' | sort | uniq -c | sort -rn   # 爆破来源统计
zgrep -h "Accepted" /var/log/auth.log* | grep -oE 'from [0-9.]+' | sort | uniq -c | sort -rn                        # 成功登录统计
iptables -L INPUT -n --line-numbers; ufw status; systemctl is-active fail2ban                                     # 防护状态
grep -E "^(PermitRootLogin|PasswordAuthentication)" /etc/ssh/sshd_config; ls /etc/ssh/sshd_config.d/              # SSH 加固状态
cat /root/.ssh/authorized_keys; stat -c '%y %n' /root/.ssh/authorized_keys                                        # 公钥与修改时间
pgrep -af pearl                                           # 挖矿进程
ps aux --sort=-%cpu | head -12                            # 高 CPU 进程
```
