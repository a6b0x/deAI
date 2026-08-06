# Docker 基础环境

本目录只负责宿主机容器基础能力，当前主要入口仍是安装脚本；`docker-compose.yml` 先保留为空服务定义，用于统一目录结构并为后续扩展预留位置。

## 文件说明

- `docker-compose.yml`：当前为空服务定义，用作本目录统一入口占位文件。
- `docker-base.install.sh`：安装 Docker Engine、Docker Compose、Buildx，并补充容器 DNS 配置。
- `docker-base.nvidia-toolkit.install.sh`：安装 NVIDIA Container Toolkit，提供 GPU 容器运行能力。

## 使用方式

安装 Docker 基础环境：

```bash
bash /root/deAI/infra/docker/docker-base.install.sh
```

安装 NVIDIA Container Toolkit：

```bash
bash /root/deAI/infra/docker/docker-base.nvidia-toolkit.install.sh
```

## 校验命令

查看版本：

```bash
docker --version
docker compose version
docker buildx version
```

验证 Docker：

```bash
docker run --rm hello-world
```

验证 GPU 容器能力：

```bash
docker run --rm --gpus all nvidia/cuda:12.4.1-base-ubuntu22.04 nvidia-smi
```

## 说明

当前机器以 `root` 用户运行，无需额外配置 `docker` 用户组。
