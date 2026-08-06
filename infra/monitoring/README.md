# Monitoring 监控系统

本目录负责宿主机、容器和 GPU 的资源监控，当前栈为 `Prometheus + Grafana + node-exporter + cAdvisor + dcgm-exporter`。

## 文件说明

- `docker-compose.yml`：监控系统主编排文件。
- `monitoring.env`：端口与 Grafana 管理员配置。
- `monitoring.start.sh`：启动脚本。
- `prometheus.yml`：Prometheus 抓取目标配置。
- `alert_rules.yml`：Prometheus 告警规则。
- `grafana-datasource.yml`：Grafana 自动数据源配置。

当前 `dcgm-exporter` 默认使用 Docker Hub 上的 `nvidia/dcgm-exporter` 公共镜像，以避免 `nvcr.io` 在未登录或受限网络场景下返回 `403 Forbidden`。

## 启动方式

推荐直接执行：

```bash
bash /root/deAI/infra/monitoring/monitoring.start.sh
```

如需手动启动：

```bash
docker compose --env-file /root/deAI/infra/monitoring/monitoring.env -f /root/deAI/infra/monitoring/docker-compose.yml up -d
```

## 访问地址

- Prometheus：`http://127.0.0.1:9090`
- Grafana：`http://127.0.0.1:3001`

实际端口以 `monitoring.env` 中配置为准。

Grafana 默认账号密码也直接来自 [monitoring.env](file:///root/deAI/infra/monitoring/monitoring.env)。

## 配置方式

本目录不再保留示例环境变量文件，直接维护现有的 [monitoring.env](file:///root/deAI/infra/monitoring/monitoring.env)。

当前默认采集目标：

- `prometheus:9090`
- `node-exporter:9100`
- `cadvisor:8080`
- `dcgm-exporter:9400`

## 告警范围

当前规则已覆盖：

- 主机 CPU、内存、磁盘使用率
- 容器 CPU、内存使用率
- 采集目标掉线
- GPU 温度与显存占用
