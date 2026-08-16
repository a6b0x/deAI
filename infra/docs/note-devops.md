# infra-registry & Registry UI 排障记录

> 时间：2026-08-04  
> 环境：`/root/deAI/infra/devops/docker-compose.yml`  
> 涉及服务：`infra-registry`（registry:2）、`infra-registry-ui`（joxit/docker-registry-ui:latest）

---

## 问题 1：infra-registry 启动失败 —— YAML 配置解析错误

### 现象

```
infra-registry | configuration error: error parsing /etc/docker/registry/config.yml: yaml: unmarshal errors:
infra-registry |   line 1: cannot unmarshal !!str `GET,HEA...` into []string
```

### 分析

`docker-compose.yml` 中配置：

```yaml
environment:
  REGISTRY_HTTP_HEADERS_Access-Control-Allow-Methods: "GET,HEAD,OPTIONS"
```

Docker Registry 通过环境变量生成 YAML 配置文件。`Access-Control-Allow-Methods` 在 YAML 中期望的是 **数组类型**（`["GET","HEAD","OPTIONS"]`），而环境变量传入的逗号分隔字符串 `"GET,HEAD,OPTIONS"` 被解析为单一字符串，导致 `unmarshal` 失败。

**根因**：环境变量格式与 YAML 数组类型不匹配。

### 解决

改为挂载自定义配置文件 `/root/deAI/infra/devops/registry-config.yml`，直接在 YAML 中声明数组：

```yaml
# docker-compose.yml
volumes:
  - ./registry-config.yml:/etc/docker/registry/config.yml:ro
```

```yaml
# registry-config.yml
http:
  headers:
    Access-Control-Allow-Methods:
      - GET
      - HEAD
      - OPTIONS
```

> 注意：`REGISTRY_HTTP_HEADERS_xxx_0`, `_1`, `_2` 索引写法也尝试过，但 `registry:2` 的环境变量映射不支持这种数组索引格式，配置不会写入 `config.yml`。

---

## 问题 2：Registry UI 页面报 CORS 错误

### 现象

```
An error occured: Check your connection and your registry must have
`Access-Control-Allow-Origin` header set to `http://localhost:5100`
```

### 分析

最初 CORS 配置为：

```yaml
Access-Control-Allow-Origin:
  - http://localhost:5100
  - http://127.0.0.1:5100
```

这导致响应中出现**两个** `Access-Control-Allow-Origin` 头：

```
Access-Control-Allow-Origin: http://localhost:5100
Access-Control-Allow-Origin: http://127.0.0.1:5100
```

根据 CORS 规范，`Access-Control-Allow-Origin` 只能有**一个值**或 `*`。浏览器收到多个不同值会拒绝该响应。

**根因**：CORS 规范不允许多个 `Access-Control-Allow-Origin` 值。

### 解决

将 Origin 改为通配符 `*`：

```yaml
Access-Control-Allow-Origin: ['*']
```

> 本地开发环境使用 `*` 无安全风险。

---

## 问题 3：修复 CORS 后页面仍报相同错误

### 现象

CORS 头已验证正确返回（`Access-Control-Allow-Origin: *`），但页面刷新后错误依旧。

### 分析

检查 `registry-ui` 容器的 nginx 配置后发现，`/v2` 反向代理块**完全被注释掉**：

```nginx
#!    location /v2 {
#!        ...
#!        proxy_pass http://registry:5000;
#!    }
```

`joxit/docker-registry-ui` 本质是 **nginx 镜像**，有两种工作模式：

| 模式 | 条件 | 前端请求路径 | |
|---|---|---|---|
| 直接模式 | 仅设 `REGISTRY_URL` | 浏览器直连 registry | |
| 代理模式 | 设 `NGINX_PROXY_PASS_URL` | 浏览器 → nginx `/v2` → registry | |

当时仅设置了 `REGISTRY_URL=http://registry:5000`，未设 `NGINX_PROXY_PASS_URL`，因此走**直接模式**。前端 JS 拿到 URL 后从浏览器直接发 AJAX 请求到 `http://registry:5000`，但 `registry` 是 Docker 内部 DNS，**浏览器无法解析**。

**根因**：反向代理未启用 + 前端拿到的是容器内部域名。

### 解决

启用代理模式：

```yaml
# docker-compose.yml -> registry-ui
environment:
  NGINX_PROXY_PASS_URL: "http://registry:5000"  # 新增：启用 nginx /v2 代理
  REGISTRY_URL: ""                               # 改为空：前端走同源路径
  DELETE_IMAGES: "true"
```

修复后请求链路：

```
浏览器 → http://localhost:5100/v2/_catalog
         → nginx (registry-ui 容器)
         → proxy_pass http://registry:5000/v2/_catalog  (Docker 内部 DNS 可达)
```

---

## 最终配置

### docker-compose.yml（registry 部分）

```yaml
  registry:
    image: registry:2
    container_name: infra-registry
    restart: unless-stopped
    ports:
      - "5000:5000"
    volumes:
      - registry_data:/var/lib/registry
      - ./registry-config.yml:/etc/docker/registry/config.yml:ro

  registry-ui:
    image: joxit/docker-registry-ui:latest
    container_name: infra-registry-ui
    restart: unless-stopped
    ports:
      - "5100:80"
    environment:
      NGINX_PROXY_PASS_URL: "http://registry:5000"
      REGISTRY_URL: ""
      DELETE_IMAGES: "true"
```

### registry-config.yml

```yaml
version: 0.1
log:
  fields:
    service: registry
storage:
  cache:
    blobdescriptor: inmemory
  filesystem:
    rootdirectory: /var/lib/registry
http:
  addr: :5000
  headers:
    X-Content-Type-Options: [nosniff]
    Access-Control-Allow-Origin: ['*']
    Access-Control-Allow-Methods:
      - GET
      - HEAD
      - OPTIONS
      - POST
      - PUT
      - DELETE
      - PATCH
    Access-Control-Allow-Headers:
      - Authorization
      - Content-Type
      - Accept
    Access-Control-Expose-Headers:
      - Docker-Content-Digest
      - Docker-Distribution-Api-Version
health:
  storagedriver:
    enabled: true
    interval: 10s
    threshold: 3
```

---

## 关键知识点

1. **Docker Registry 环境变量映射不支持嵌套数组**：复杂的 `headers` 配置应使用自定义 `config.yml` 挂载
2. **CORS `Access-Control-Allow-Origin` 只能是单值或 `*`**：多值会导致浏览器拒绝
3. **`joxit/docker-registry-ui` 的工作模式**：由 `NGINX_PROXY_PASS_URL` 控制是否启用 nginx 反向代理；仅设 `REGISTRY_URL` 则前端直连，URL 必须浏览器可达
