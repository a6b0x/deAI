# 类别

## 基础信息
260806
- 系统：Ubuntu 22.04.5 LTS，内核 6.8.0-136-generic
- 运行时长：9 天 11 小时（2026-07-28 09:53 启动）
- 有效用户：root、user（uid 1000）
- 当前以 root 身份操作

## 网络暴露面
260806
- sshd 监听 0.0.0.0:22（全接口）
- Docker 容器 infra-gitea 映射 0.0.0.0:2222→容器内 22
- XRDP 监听 *:3389（全网）
- 多个 Docker 服务暴露：3000、3100、5000、5001、5100、8082、9090、9400
- iptables INPUT 链策略为 ACCEPT，无入站过滤
- 无 fail2ban 防护

## 攻击现象
260806
- 来源 IP 194.59.30.26（荷兰）对 SSH 发起持续暴力破解
- 累计失败尝试 7337+ 次，集中在 2026-08-05
- 攻击字典包含大量中文人名拼音（zhaoxz、chenghao、xiaoan 等）及常见账号（test、dell、ubuntu、lenovo、admin）
- 攻击路径：公网端口映射穿透至内网 10.8.0.8:22，非内部发起
- 攻击者通过全端口扫描发现 SSH Banner 后定向爆破

## 登录审计
260806
- root 成功登录来源：123.139.156.2（73 次）、111.19.41.247（34 次）
- 均使用 publickey 认证，需确认是否为授权设备
- 历史记录出现 36.163.171.42 对 root 的登录（2026-07-28）
- root 和 user 的 authorized_keys 均包含 x@MacBook24.local 公钥

## 可疑进程
260806
- /root/deAI/pearl/pearl-miner 持续运行，连接矿池 pool.pearlhash.xyz:9000
- CPU 占用约 3.5%，日志 miner.log 约 13MB
- awesun（向日葵）和 rustdesk 两个远程控制软件长期运行
- rustdesk 由 root 每小时通过 sudo 启动，以 gdm 用户运行

## 权限与配置
260806
- /etc/ssh/sshd_config 中 PermitRootLogin、PasswordAuthentication 均被注释（默认允许）
- 无 /etc/ssh/sshd_config.d/ 扩展配置
- SUID 文件均为系统标准文件，无异常新增
- /tmp、/var/tmp 未发现明显恶意文件
- 计划任务为系统默认，无异常 crontab

## 关键排查步骤
260806
1. 执行 `ss -tlnp` 确认所有监听端口及其归属进程
2. 执行 `last` 和 `grep Accepted /var/log/auth.log` 梳理成功登录来源 IP 与认证方式
3. 执行 `grep "Failed password\|Invalid user" /var/log/auth.log` 统计暴力破解来源与频率
4. 执行 `cat ~/.ssh/authorized_keys` 核对所有公钥指纹及对应设备
5. 执行 `ps aux --sort=-%cpu` 检查高 CPU 占用进程及异常命令行参数
6. 执行 `iptables -L -n` 和 `ufw status` 检查防火墙入站策略
7. 执行 `find / -perm -4000 -type f` 排查异常 SUID 提权文件
8. 执行 `find /tmp /var/tmp /dev/shm -type f -newer /tmp` 检查临时目录可疑新增文件
9. 执行 `crontab -l` 和 `ls /etc/cron.d/` 检查异常计划任务
10. 执行 `docker ps --format "{{.Names}}\t{{.Ports}}"` 确认容器端口映射是否过度暴露

## 解决方案概述
260806
1. 确认 123.139.156.2 和 111.19.41.247 是否为授权管理 IP，若不是则立即从 authorized_keys 移除对应公钥并轮换密钥
2. 安装并配置 fail2ban，针对 sshd 设置 maxretry=3、bantime=3600，自动封锁暴力破解源
3. 修改 /etc/ssh/sshd_config：设置 PermitRootLogin no、PasswordAuthentication no、PubkeyAuthentication yes，仅允许密钥登录且禁止 root 直接登录
4. 配置 iptables 或 ufw：限制 22 端口仅允许可信 IP 段访问，关闭 3389 全网暴露或限制来源
5. 评估 infra-gitea 的 2222 端口是否必须全网暴露，必要时改为仅监听 127.0.0.1 或添加 IP 白名单
6. 确认 pearl-miner 是否为自行部署，若不是则终止进程、清除 /root/deAI/pearl/ 目录并审计植入路径
7. 审计 awesun 和 rustdesk 的访问控制，确认密码强度与连接白名单，关闭不必要的远程控制服务
8. 考虑将 SSH 公网映射端口改为非标准高位端口（如 5xxxx）并结合端口敲门或 VPN 接入，减少扫描暴露面
