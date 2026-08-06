# DevOps 基础设施

本目录提供 CI/CD 流水线所需的基础服务：**Gitea（代码托管）+ 私有 Docker 镜像仓库**。

## 文件说明

- `docker-compose.yml`：Gitea + Registry 服务编排。
- `pipeline.sh`：CI/CD 流水线入口（测试 → 构建 → 推送 → 部署）。

## 启动方式

```bash
docker compose -f /root/deAI/infra/devops/docker-compose.yml up -d
```

## 访问地址

- Gitea：`http://127.0.0.1:3100`（首次访问需完成安装向导）
- 镜像仓库 API：`http://127.0.0.1:5000`
- 镜像仓库管理界面：`http://127.0.0.1:5100`

## 流水线流程

```
代码推送至 Gitea → 本地测试 → 构建镜像 → 推送至私有仓库 → 服务器拉取部署
```

## 依赖

- Docker Engine 与 Docker Compose（由 `infra/docker/` 提供）