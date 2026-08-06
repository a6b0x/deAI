#!/usr/bin/env bash

set -euo pipefail

# GPU 运行时会修改宿主机 Docker 配置，必须以 root 身份执行。
if [[ "${EUID}" -ne 0 ]]; then
  echo "请使用 root 运行该脚本。"
  exit 1
fi

# 配置 NVIDIA Container Toolkit 软件源和签名。
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey \
  | gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg

curl -fsSL https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list \
  | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' \
  > /etc/apt/sources.list.d/nvidia-container-toolkit.list

# 安装工具并把 nvidia runtime 接入 Docker。
apt-get update
apt-get install -y nvidia-container-toolkit
nvidia-ctk runtime configure --runtime=docker
systemctl restart docker
