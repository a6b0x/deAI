# 多租户共享单机：每团队 compose 模板（配额写死）

> 任务4产物。方案背景见 `../docs/note-docker.md`：单台 Ubuntu 22（EPYC 7302 16C/32T + 128G + 双 RTX 4090 24G + 2TB NVMe）供多个内部团队共享，采用 Docker Compose 软隔离，配合 Portainer（`/root/edge/portainer`）管理。

## 一、团队划分与配额总账

**配额写死原则**：每个团队模板中 `deploy.resources` 为硬编码，不使用 `${VAR}` 占位，团队无法自行修改。配额变更统一走 infra 负责人审批，改模板 + 同步本总账。

| 团队 | 目录 | 项目名 | CPU(cpus) | 内存 | GPU(device_ids) | 端口段 | PID |
|------|------|--------|-----------|------|------------------|--------|-----|
| AI 推理/算法 | `ai/` | `team-ai` | 7.0 | 56G | `["0"]` 1×4090 | 18100+ | 1024 |
| 数据工程 | `data/` | `team-data` | 3.5 | 32G | — | 18200+ | 512 |
| 应用开发 | `app/` | `team-app` | 3.0 | 24G | — | 18300+ | 512 |
| 基础设施/DevOps | `infra/` | `team-infra` | 1.0 | 8G | — | 18400+ | 512 |
| **合计** | | | **14.5** | **120G** | 卡0 | | |
| **宿主保留** | | | ~1.5 | ~8G | 卡1（矿工等） | | |

> CPU 按 16 核计（逻辑核 32 线程，`cpus` 以逻辑核计则需减半，见下文注意事项）。

## 二、目录结构

```
/root/deAI/infra/teams/
├── README.md              # 本文档：配额总账 + 使用说明
├── ai/                    # AI 推理/算法团队
│   ├── docker-compose.yml # 配额写死 + 占位示例服务
│   └── .env.example
├── data/
│   ├── docker-compose.yml
│   └── .env.example
├── app/
│   ├── docker-compose.yml
│   └── .env.example
└── infra/
    ├── docker-compose.yml
    └── .env.example
```

## 三、快速开始

```bash
# 1. 进入团队目录（以 ai 为例），复制 .env 并填写端口/业务变量
cd /root/deAI/infra/teams/ai
cp .env.example .env

# 2. 将模板中占位 nginx 服务替换为团队真实镜像与配置

# 3. 启动 / 查看配置 / 停止
docker compose up -d
docker compose config --quiet && echo "语法OK"   # 校验
docker compose down
```

Portainer 方式：在 Portainer → Stacks 中粘贴模板或关联本目录即可托管部署（需先在 dind 环境内使用）。

## 四、GPU 说明（重要）

- 4090 **无法整卡切分**，当前采用**整卡透传**：`dind-platform`（`/root/edge/portainer`）已将 `/dev/nvidia0` 穿透进第 2 层 dockerd，并安装 nvidia-container-toolkit。
- 团队模板中 GPU 用标准写法：
  ```yaml
  deploy:
    resources:
      reservations:
        devices:
          - driver: nvidia
            device_ids: ["0"]
            capabilities: [gpu]
  ```
- 卡0 配额给 `ai`，卡1 保留宿主（矿工/vLLM 独占场景）。若需单卡多团队切分（vGPU），须引入 HAMi（见 `../docs/note-docker.md` 选型），本方案暂不涉及。
- **宿主保留额度仅软约束**：Docker Compose 的配额无法对宿主进程限速，docker daemon / mihomo / portainer 等自身负载需人工控制，勿超售。

## 五、网络 / 端口 / DNS / 日志

- 每团队独立 bridge 网络（`team-<x>-net`），与宿主机其他 compose 项目网络隔离。
- 端口段隔离（18100+ / 18200+ / 18300+ / 18400+），避开已占用端口（18000 vLLM、8080 WebUI、8008/8443 Rancher、9443 Portainer 等）。
- DNS 显式指定 `223.5.5.5` / `119.29.29.29`：宿主 mihomo 透明代理为 fake-ip 模式，仅接管宿主机流量，**Docker 桥接容器必须走真实 DNS**，否则外网超时（见 `../docs/note-docker.md`）。
- 日志限制 `max-size: 20m / max-file: 3`：多团队共享 2TB NVMe，防日志吃满磁盘。

## 六、调整配额流程

1. 修改对应 `docker-compose.yml` 的 `deploy.resources.limits/reservations`（硬编码值）。
2. 同步更新本 README 配额总账，确保总额不超卖（CPU ≤ ~16、内存 ≤ ~120G、GPU ≤ 2 卡）。
3. 通知相关团队重启应用：`docker compose up -d`（仅新增 limit 时需 recreate：`docker compose up -d --force-recreate`）。

## 变更记录

- 2026-08-19 初版：按宿主硬件（16C/128G/双4090）划分 ai/data/app/infra 四团队，配额写死。
