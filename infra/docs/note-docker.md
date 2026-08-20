# Docker+容器化

## 多租户共享资源方案选型：内部团队软隔离足够，选 K3s+HAMi+Rancher 260818

**需求**：单台 Ubuntu 22（EPYC 7302 + 128G + 双 RTX 4090 + 2TB NVMe）供多个内部团队共享资源。

**关键判断**：内部团队为可信环境，**软隔离（容器 + K8s）足够**，无需虚拟机硬隔离。

| 候选 | 结论 | 原因 |
|---|---|---|
| Proxmox VE | 否决 | 需重装操作系统，代价大 |
| Sealos | 否决 | 面向公有云 K8s 交付，偏重 |
| 1Panel / Coolify | 不匹配 | 应用托管面板，解决"部署应用"，不解决"多租户共享资源" |
| K3s + HAMi + Rancher | **选用** | K3s 轻量单机 K8s；HAMi 做 GPU 虚拟化切分（vGPU）共享双 4090；Rancher 做多集群管理平面并可纳管 K3s |

配套参考：KAI-Scheduler（GPU 调度）、vLLM（推理引擎）、LiteLLM（网关），属资源池组件而非管理面。Rancher v2.14 官方已弃用 Docker 单容器方式，推荐 Helm on K3s（见下文部署中止条目）。

## Rancher 部署中止：HTTP 访问 302 跳 HTTPS（控制台用 https://IP:8443），宿主 k3s 已卸载无残留 260818

**访问**：Rancher 单机 Docker 方式 `http://IP:8008` 会 302 强制跳 HTTPS，正确访问 `https://IP:8443`（自签证书需浏览器信任）。端口映射 `8008:80`（HTTP）/ `8443:443`（HTTPS），已避让宿主已有端口（18000/5901/5100/5000/2222/3100/9400/9090/3000/8082/9100）。

**中止原因**：内嵌 k3s 存在 fake-ip 断网与镜像拉取问题（见下方条目），且官方推荐路径为 Helm on K3s。最终 `docker compose down` 停止容器；宿主 k3s 用 `/usr/local/bin/k3s-uninstall.sh` 卸载，helm 实际从未安装成功，验证无残留（k3s/kubectl/crictl/helm 均不存在，无 k3s systemd 服务）。

**K3s 官方安装命令**（如后续重试）：

```bash
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="server --disable traefik --write-kubeconfig-mode 644" sh -
```

## Docker 桥接容器外网超时：mihomo fake-ip 只接管宿主机流量，需显式指定真实 DNS 260818

**现象**：Rancher 容器内嵌 k3s 的系统镜像（coredns/pause/helm-operation 等）全部拉取失败，Pod 卡 `ContainerCreating`，界面报 `API Aggregation not ready`。

**根因**：宿主 mihomo 透明代理为 fake-ip 模式，DNS 把所有域名解析到 `198.18.0.x`；但代理只接管宿主机流量，**Docker 桥接网络容器的流量不走代理**——容器拿到 fake-ip 地址却无真实出口，全部外网超时。

**修复**：compose 中给容器指定真实 DNS，走默认网关真实出口联网：

```yaml
dns:
  - 223.5.5.5        # 阿里 DNS（真实解析，绕过 fake-ip）
  - 119.29.29.29     # 腾讯 DNS（备用）
```

验证：容器内 `curl baidu.com` 返回 200 即网络恢复。

**注意**：若改用 `network_mode: host`，容器虽可联网，但会与宿主上已运行的 k3s 等服务的端口（6443/2379/2380）冲突崩溃——多套 K8s/服务共存应走桥接独立网络命名空间。

## 内嵌 k3s 的 containerd 不读宿主 docker daemon.json，镜像加速需单独挂载 registries.yaml 260818

**现象**：宿主 `/etc/docker/daemon.json` 已配镜像加速，但 Rancher 容器内嵌 k3s（containerd）拉镜像仍直连 Docker Hub 失败。

**根因**：containerd 与 dockerd 各自维护镜像配置，内嵌 k3s 只读 `/etc/rancher/k3s/registries.yaml`，与宿主 docker daemon.json 无关。

**修复**：挂载自定义加速配置到容器内该路径：

```yaml
volumes:
  - ./registries.yaml:/etc/rancher/k3s/registries.yaml:ro
```

```yaml
# registries.yaml
mirrors:
  docker.io:
    endpoint:
      - "https://docker.mirrors.ustc.edu.cn"
      - "https://hub-mirror.c.163.com"
  quay.io:
    endpoint:
      - "https://quay.mirrors.ustc.edu.cn"
  ghcr.io:
    endpoint:
      - "https://ghcr.mirrors.ustc.edu.cn"
```

**注意**：重复构建内嵌 k3s 的容器前应先清空数据目录（如 `/var/lib/rancher` 挂载点），残留数据会导致配置不生效。

## 镜像源可用性：registry-1.docker.io 直连超时，dockerproxy.net 可用 260818

| 源 | 结果 |
|---|---|
| `https://dockerproxy.net/v2/` | 200（可用） |
| `https://docker.1ms.run/v2/` | 401（registry 正常，需认证路径） |
| `registry-1.docker.io` 直连 | 超时 |

docker.io 镜像加速建议优先使用中科大/网易镜像（见上一条），或 `dockerproxy.net`。

## VS Code 无法在 GUI 中浏览容器挂载数据 260805

**现象**

在 VS Code 远程 SSH 连接服务器后，通过 Docker 面板右键 Volume →「在容器中查看」时，一直卡在：

> 正在启动 Docker (显示日志)

终端日志显示正在不断重试拉取镜像：

```
docker pull mcr.microsoft.com/devcontainers/base:0-alpine-3.20
```

**相关环境**


| 组件           | 版本/信息                                                    |
| -------------- | ------------------------------------------------------------ |
| VS Code        | Remote-SSH 连接                                              |
| Docker 扩展    | `ms-azuretools.vscode-containers` v2.4.5                     |
| Docker Engine  | 29.6.2 (Community)                                           |
| Docker Compose | v5.3.1 (plugin，`docker compose` 命令可用)                   |
| 代理           | mihomo (Clash Meta) TUN 模式 + fake-ip，监听`127.0.0.1:7890` |

**根因**

两个问题叠加：

- **问题一：Docker 扩展自身的 Compose 自动检测卡住**。扩展启动时会自动检测 Docker Compose 命令，在远程 SSH 场景下可能卡在 `Attempting to autodetect Docker Compose command...`，导致 Docker 面板树视图反复 `Canceled`，无法正常刷新。
- **问题二（核心）：`mcr.microsoft.com` 在国内无法访问**。右键 Volume →「在容器中查看」时，VS Code 内部会启动一个临时容器挂载 volume 来浏览文件，默认使用 `mcr.microsoft.com/devcontainers/base:0-alpine-3.20` 作为辅助镜像。该域名在国内被全面封锁：DNS 被劫持为 `198.18.0.251`（mihomo fake-ip 段），真实 IP `150.171.70.10` 直连超时 / SSL 握手失败，代理节点也无法到达。镜像永远拉不下来，界面永远卡住。

**解决方案**

不依赖 VS Code GUI，直接终端浏览 volume 数据：

```bash
# 用 Docker Hub 可拉取的 alpine 镜像挂载 volume 并浏览
docker run --rm -it -v <volume_name>:/mnt alpine sh

# 进入容器后
ls -la /mnt
```

如果是 bind mount 类型的挂载，直接在宿主机上查看对应目录即可。

`"docker.composeCommand": "docker compose"` 设置无效，不需要添加：它只能解决 Docker 扩展自身的 Compose 检测卡住问题，无法绕过 mcr.microsoft.com 的网络封锁——卷浏览功能拉取的是 Dev Container 辅助镜像，与 Compose 命令配置无关。

**验证**

```bash
docker run --rm -it -v <volume_name>:/mnt alpine ls -la /mnt
```

应能正常列出 volume 中的所有文件。

**参考**

- VS Code Docker 扩展: [ms-azuretools.vscode-docker](https://marketplace.visualstudio.com/items?itemName=ms-azuretools.vscode-docker)
- mcr.microsoft.com 状态：国内 DNS 劫持 + IP/代理全封锁
