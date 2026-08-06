#!/bin/bash
set -euo pipefail

# ============== 配置区 ==============
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MINER_BIN="${SCRIPT_DIR}/pearl-miner"
LOG_FILE="${SCRIPT_DIR}/miner.log"
PID_FILE="${SCRIPT_DIR}/miner.pid"

# 挖矿配置 - 优先从环境变量读取，未设置则用默认值
POOL_HOST="${POOL_HOST:-pool.pearlhash.xyz:9000}"
USER_ADDRESS="${USER_ADDRESS:-prl1pldsjzegmcujgsp5rlhslp4gyg6zvkcqq2czmpqrptezay0pcmd8sveydvl}"
WORKER_NAME="${WORKER_NAME:-$(hostname)}"
POOL_HOSTNAME="${POOL_HOST%%:*}"
POOL_PORT="${POOL_HOST##*:}"

# 日志轮转: 超过 50MB 自动归档
LOG_MAX_SIZE=$((50 * 1024 * 1024))
# ====================================

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
log()  { echo -e "${GREEN}[INFO]${NC}  $(date '+%Y-%m-%d %H:%M:%S') $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC}  $(date '+%Y-%m-%d %H:%M:%S') $*"; }
err()  { echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') $*" >&2; }

check_prerequisites() {
    if [[ ! -f "$MINER_BIN" ]]; then
        err "找不到矿工程序: $MINER_BIN"
        exit 1
    fi
    if [[ ! -x "$MINER_BIN" ]]; then
        warn "矿工程序无执行权限，正在添加..."
        chmod +x "$MINER_BIN"
    fi
    if command -v nvidia-smi &>/dev/null; then
        local gpu_count
        gpu_count=$(nvidia-smi --list-gpus 2>/dev/null | wc -l)
        log "检测到 GPU 数量: $gpu_count"
    else
        warn "未检测到 nvidia-smi，请确认 GPU 驱动已安装"
    fi
}

resolve_host_ip() {
    local host="$1"
    local resolved_ip=""

    if command -v getent &>/dev/null; then
        resolved_ip=$(getent ahostsv4 "$host" 2>/dev/null | awk 'NR==1 {print $1}')
        [[ -n "$resolved_ip" ]] || resolved_ip=$(getent hosts "$host" 2>/dev/null | awk 'NR==1 {print $1}')
    fi

    if [[ -z "$resolved_ip" ]] && command -v nslookup &>/dev/null; then
        resolved_ip=$(nslookup "$host" 2>/dev/null | awk '/^Address: / {print $2}' | tail -1)
    fi

    if [[ -z "$resolved_ip" ]] && command -v host &>/dev/null; then
        resolved_ip=$(host "$host" 2>/dev/null | awk '/has address/ {print $NF; exit}')
    fi

    printf '%s\n' "$resolved_ip"
}

check_pool_network() {
    local resolved_ip=""

    if [[ -z "$POOL_HOSTNAME" ]]; then
        err "矿池地址无效: $POOL_HOST"
        exit 1
    fi

    resolved_ip=$(resolve_host_ip "$POOL_HOSTNAME")
    if [[ -z "$resolved_ip" ]]; then
        err "无法解析矿池域名: $POOL_HOSTNAME"
        warn "请先确认本机网络已就绪。你这台机器当前依赖 Clash 虚拟网卡/TUN 才能解析该矿池域名。"
        warn "确认 Clash 已启动且虚拟网卡已打开后，再重新执行启动命令。"
        exit 1
    fi

    log "矿池域名解析正常: $POOL_HOSTNAME -> $resolved_ip"

    # TCP 预检查只做提示，不作为硬失败条件，避免远端短暂抖动影响启动。
    if command -v timeout &>/dev/null && [[ "$POOL_PORT" =~ ^[0-9]+$ ]]; then
        if timeout 5 bash -c "exec 3<>/dev/tcp/$POOL_HOSTNAME/$POOL_PORT" 2>/dev/null; then
            log "矿池端口连通性正常: $POOL_HOSTNAME:$POOL_PORT"
        else
            warn "矿池端口暂时不可达: $POOL_HOSTNAME:$POOL_PORT"
            warn "如果刚打开 Clash 虚拟网卡，建议等待几秒后重试。"
        fi
    fi
}

rotate_log() {
    if [[ -f "$LOG_FILE" ]] && [[ $(stat -c%s "$LOG_FILE" 2>/dev/null || echo 0) -gt $LOG_MAX_SIZE ]]; then
        log "日志超过 50MB，归档为 ${LOG_FILE}.old"
        mv -f "$LOG_FILE" "${LOG_FILE}.old"
    fi
}

is_running() {
    if [[ -f "$PID_FILE" ]]; then
        local pid
        pid=$(cat "$PID_FILE" 2>/dev/null)
        if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
            return 0
        fi
        rm -f "$PID_FILE"
    fi
    return 1
}

append_log_session_marker() {
    {
        echo ""
        echo "==================== $(date '+%Y-%m-%d %H:%M:%S') ===================="
        echo "Starting Pearl Miner | pool=${POOL_HOST} | worker=${WORKER_NAME}"
    } >> "$LOG_FILE"
}

start_miner() {
    if is_running; then
        warn "矿工已在运行 (PID: $(cat "$PID_FILE"))"
        return 0
    fi
    check_prerequisites
    check_pool_network
    rotate_log
    append_log_session_marker

    log "========================================"
    log "启动 Pearl Miner"
    log "矿池:        $POOL_HOST"
    log "钱包地址:    ${USER_ADDRESS:0:12}...${USER_ADDRESS: -8}"
    log "工作者名称:  $WORKER_NAME"
    log "日志文件:    $LOG_FILE"
    log "========================================"

    nohup "$MINER_BIN" \
        --host "$POOL_HOST" \
        --user "$USER_ADDRESS" \
        --worker "$WORKER_NAME" \
        >> "$LOG_FILE" 2>&1 &

    local pid=$!
    echo "$pid" > "$PID_FILE"
    sleep 1

    if kill -0 "$pid" 2>/dev/null; then
        log "矿工启动成功! PID: $pid"
        log "查看日志: tail -f $LOG_FILE"
    else
        err "矿工启动失败，请检查日志: tail -50 $LOG_FILE"
        rm -f "$PID_FILE"
        exit 1
    fi
}

stop_miner() {
    if ! is_running; then
        warn "矿工未在运行"
        return 0
    fi
    local pid
    pid=$(cat "$PID_FILE")
    log "正在停止矿工 (PID: $pid)..."
    kill "$pid" 2>/dev/null || true
    for _ in {1..10}; do
        kill -0 "$pid" 2>/dev/null || break
        sleep 0.5
    done
    if kill -0 "$pid" 2>/dev/null; then
        warn "进程未响应 SIGTERM，强制终止..."
        kill -9 "$pid" 2>/dev/null || true
    fi
    rm -f "$PID_FILE"
    log "矿工已停止"
}

status_miner() {
    if is_running; then
        local pid
        pid=$(cat "$PID_FILE")
        log "矿工运行中 | PID: $pid | 运行时长: $(ps -o etime= -p "$pid" 2>/dev/null || echo N/A)"
        if [[ -f "$LOG_FILE" ]]; then
            local last_hash
            last_hash=$(grep -oP 'Hashrate Total = \K[0-9.]+ .*' "$LOG_FILE" | tail -1)
            [[ -n "$last_hash" ]] && log "最近算力: $last_hash"
        fi
    else
        warn "矿工未在运行"
        return 1
    fi
}

case "${1:-start}" in
    start)   start_miner ;;
    stop)    stop_miner ;;
    restart) stop_miner; sleep 1; start_miner ;;
    status)  status_miner ;;
    *)
        echo "用法: $0 {start|stop|restart|status}"
        echo "  start   - 启动矿工（后台运行）"
        echo "  stop    - 停止矿工"
        echo "  restart - 重启矿工"
        echo "  status  - 查看运行状态"
        echo ""
        echo "环境变量覆盖配置:"
        echo "  POOL_HOST, USER_ADDRESS, WORKER_NAME"
        exit 1
        ;;
esac
