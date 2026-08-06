#!/usr/bin/env bash
# Step 2: 启动节点 (仅节点, 不挖矿) — 用于先同步区块链 / 后续创建钱包需要 RPC 可达
# 参考: https://docs.discrete.cash/#/operators/node-operation
#   文档命令:
#     discreted \
#       --p2p-bind-ip 0.0.0.0 --p2p-bind-port 9330 \
#       --rpc-bind-ip 127.0.0.1 --rpc-bind-port 9331
# 目的: 让本地节点同步主网链数据, 并在 127.0.0.1:9331 提供 RPC (给 simplewallet 创建钱包时用)
# 预期结果: 进程在后台运行; ss/netstat 能看到 0.0.0.0:9330 LISTEN (P2P) + 127.0.0.1:9331 LISTEN (RPC)
#           日志 logs/discreted.log 出现 "RPC server started successfully"

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${PROJECT_DIR}"

DAEMON="$(pwd)/bin/discreted"
PIDFILE="$(pwd)/run/discreted.pid"
LOGFILE="$(pwd)/logs/discreted.log"
DATADIR="$(pwd)/data"

mkdir -p logs run data wallet config

if [[ -f "$PIDFILE" ]] && kill -0 "$(cat $PIDFILE)" 2>/dev/null; then
  echo "[跳过] discreted 已在运行 (PID $(cat $PIDFILE))"
  exit 0
fi
rm -f "$PIDFILE"

echo "[执行] 启动 discreted (后台, 不挖矿)..."
nohup "${DAEMON}" \
  --data-dir "${DATADIR}" \
  --log-file "${LOGFILE}" \
  --p2p-bind-ip 0.0.0.0 \
  --p2p-bind-port 9330 \
  --rpc-bind-ip 127.0.0.1 \
  --rpc-bind-port 9331 \
  --log-level 2 \
  --no-console \
  >> "${LOGFILE}" 2>&1 &

echo $! > "${PIDFILE}"
sleep 3

echo ""
echo "[检查] 进程:"
ps -o pid,etime,%cpu,%mem,cmd -p "$(cat $PIDFILE)" 2>/dev/null || echo "  (进程不存在? 看 logs/discreted.log)"

echo ""
echo "[检查] 监听端口 (需要看到 9330 和 9331):"
(ss -tlnp 2>/dev/null || netstat -tlnp 2>/dev/null) | grep -E ":(9330|9331)" || echo "  (未发现监听端口? 等几秒再运行 scripts/check.sh)"

echo ""
echo "[提示] 日志: tail -f logs/discreted.log"
echo "[完成] Step 2. 下一步: scripts/step3-create-wallet.sh"
