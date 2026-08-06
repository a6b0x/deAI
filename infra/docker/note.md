# VS Code 查看容器挂载数据卡住问题

## 现象

在 VS Code 远程 SSH 连接服务器后，通过 Docker 面板右键 Volume →「在容器中查看」时，一直卡在：

> 正在启动 Docker (显示日志)

终端日志显示正在不断重试拉取镜像：

```
docker pull mcr.microsoft.com/devcontainers/base:0-alpine-3.20
```

## 相关环境

| 组件 | 版本/信息 |
|------|----------|
| VS Code | Remote-SSH 连接 |
| Docker 扩展 | `ms-azuretools.vscode-containers` v2.4.5 |
| Docker Engine | 29.6.2 (Community) |
| Docker Compose | v5.3.1 (plugin，`docker compose` 命令可用) |
| 代理 | mihomo (Clash Meta) TUN 模式 + fake-ip，监听 `127.0.0.1:7890` |

## 根因分析

### 两个问题叠加

**问题一：Docker 扩展自身的 Compose 自动检测卡住**

扩展启动时会自动检测 Docker Compose 命令，在远程 SSH 场景下可能卡在：

```
Attempting to autodetect Docker Compose command...
```

这导致 Docker 面板树视图反复 `Canceled`，无法正常刷新。

**问题二（核心）：`mcr.microsoft.com` 在国内无法访问**

右键 Volume →「在容器中查看」时，VS Code 内部会启动一个临时容器挂载 volume 来浏览文件，默认使用 `mcr.microsoft.com/devcontainers/base:0-alpine-3.20` 作为辅助镜像。

该域名在国内被全面封锁：

1. **DNS 劫持**：`mcr.microsoft.com` 被解析为 `198.18.0.251`（mihomo fake-ip 段），非真实 Microsoft IP
2. **真实 IP 直连失败**：真实 IP `150.171.70.10` 直连超时 / SSL 握手失败
3. **代理节点也无法到达**：mihomo 代理节点同样无法连接 mcr

综上，镜像永远拉不下来，界面永远卡住。

## 解决方案

### 不依赖 VS Code GUI，直接终端浏览 volume 数据

```bash
# 用 Docker Hub 可拉取的 alpine 镜像挂载 volume 并浏览
docker run --rm -it -v <volume_name>:/mnt alpine sh

# 进入容器后
ls -la /mnt
```

如果是 bind mount 类型的挂载，直接在宿主机上查看对应目录即可。

### 为什么不用 `docker.composeCommand` 设置

`"docker.composeCommand": "docker compose"` 只能解决 Docker 扩展自身的 Compose 检测卡住问题，无法绕过 mcr.microsoft.com 的网络封锁。卷浏览功能拉取的是 Dev Container 辅助镜像，与 Compose 命令配置无关，因此此设置无效，不需要添加。

## 验证

终端执行：

```bash
docker run --rm -it -v <volume_name>:/mnt alpine ls -la /mnt
```

应能正常列出 volume 中的所有文件。

## 参考

- VS Code Docker 扩展: [ms-azuretools.vscode-docker](https://marketplace.visualstudio.com/items?itemName=ms-azuretools.vscode-docker)
- mcr.microsoft.com 状态：国内 DNS 劫持 + IP/代理全封锁

---

*排查日期: 2026-08-05*
