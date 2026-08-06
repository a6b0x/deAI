#!/usr/bin/env bash
# Step 4: 停掉不挖矿的节点 → 启动 Headless 挖矿 daemon
# 参考: https://docs.discrete.cash/#/operators/mining  章节 "Headless daemon"
#   文档命令:
#     discreted \
#       --mining-wallet /secure/miner.wallet \
#       --mining-password-file /secure/miner-password.txt \
#       --mining-threads 4 \
#       --no-console
# 目的: 用钱包的 PQ 身份 (spend key) 进行 Solo CPU 挖矿 (DiscretePower: ML-DSA-65 + yespower-discrete)
# 准备: 需要先在 wallet/miner-password.txt 中写入你刚才设置的钱包密码 (只有一行).
#       例:  echo -n '你的密码' > wallet/miner-password.txt ; chmod 600 wallet/miner-password.txt
# 预期结果:
#   - 进程在后台运行 (run/discreted.pid)
#   - logs/discreted.log 中能看到 mining 相关 INFO
#   - scripts/check.sh 的 RPC 诊断里 mining_active / mining_thread_count 有值
#   - 挖到块后奖励进入 wallet/miner.wallet (等 coinbase maturity 到期解锁)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${PROJECT_DIR}"

DAEMON="$(pwd)/bin/discreted"
WALLET="$(pwd)/wallet/miner.wallet"
PWDFILE="$(pwd)/wallet/miner-password.txt"
PIDFILE="$(pwd)/run/discreted.pid"
LOGFILE="$(pwd)/logs/discreted.log"
DATADIR="$(pwd)/data"

# 默认线程数 = 物理核数 (DiscretePower 是整数重算力, 超线程 SMT 收益很有限).
# 你可以显式覆盖:  scripts/step4-start-mining.sh  12
PHYSICAL_CORES="$(grep '^core id' /proc/cpuinfo 2>/dev/null | sort -u | wc -l)"
[[ "${PHYSICAL_CORES:-0}" -lt 1 ]] && PHYSICAL_CORES="$(nproc)"
THREADS="${1:-${PHYSICAL_CORES}}"

echo ""
echo "╔══════════════════════════════════════════════════════════════════╗"
echo "║  自动检测硬件推荐: 物理核=${PHYSICAL_CORES}   逻辑核=$(nproc)        ║"
echo "║  DiscretePower (ML-DSA-65 + yespower) 为整数算力, SMT 增益低。     ║"
echo "║  建议: 线程数 <= 物理核数, 留 0~4 核给其它服务。                     ║"
echo "╚══════════════════════════════════════════════════════════════════╝"
echo "[参数] 实际使用的挖矿线程数 = ${THREADS}   (手动覆盖: $0 <N>)"
echo ""

# 检查
[[ -x "${DAEMON}" ]]  || { echo "[错误] 缺 bin/discreted, 跑 step1"; exit 1; }
[[ -f "${WALLET}" ]]  || { echo "[错误] 缺 ${WALLET}, 先跑 step3 创建钱包"; exit 1; }
[[ -f "${PWDFILE}" ]] || {
  echo "[错误] 缺 ${PWDFILE}. 请先把你 step3 设置的钱包密码写进去, 例如:"
  echo "    echo -n '你的密码' > wallet/miner-password.txt  &&  chmod 600 wallet/miner-password.txt"
  exit 1
}
chmod 600 "${PWDFILE}" 2>/dev/null || true

mkdir -p logs run data wallet config

# 先停掉旧的
if [[ -f "${PIDFILE}" ]]; then
  OPID="$(cat ${PIDFILE})"
  if kill -0 "${OPID}" 2>/dev/null; then
    echo "[清理] 停止旧节点 PID=${OPID} (SIGTERM)..."
    kill -TERM "${OPID}" 2>/dev/null || true
    for i in 1 2 3 4 5 6 7 8 9 10; do
      kill -0 "${OPID}" 2>/dev/null || break
      sleep 1
    done
    kill -0 "${OPID}" 2>/dev/null && { echo "[强杀] SIGKILL PID=${OPID}"; kill -9 "${OPID}" 2>/dev/null || true; }
  fi
  rm -f "${PIDFILE}"
fi

echo ""
echo "[执行] 启动 Headless 挖矿节点..."
echo "  --mining-wallet         ${WALLET}"
echo "  --mining-password-file  ${PWDFILE}"
echo "  --mining-threads        ${THREADS}"
echo "  --data-dir              ${DATADIR}"
echo "  --log-file              ${LOGFILE}"
echo ""

nohup "${DAEMON}" \
  --data-dir "${DATADIR}" \
  --log-file "${LOGFILE}" \
  --p2p-bind-ip 0.0.0.0 \
  --p2p-bind-port 9330 \
  --rpc-bind-ip 127.0.0.1 \
  --rpc-bind-port 9331 \
  --log-level 2 \
  --mining-wallet "${WALLET}" \
  --mining-password-file "${PWDFILE}" \
  --mining-threads "${THREADS}" \
  --no-console \
  >> "${LOGFILE}" 2>&1 &

echo $! > "${PIDFILE}"
sleep 4

echo "[检查] 进程 PID=$(cat ${PIDFILE}):"
ps -o pid,etime,%cpu,%mem,cmd -p "$(cat ${PIDFILE})" 2>/dev/null || echo "  (未运行, 看 logs/discreted.log 尾 30 行: tail -30 logs/discreted.log)"

echo ""
echo "[检查] 端口:"
(ss -tlnp 2>/dev/null || netstat -tlnp 2>/dev/null) | grep -E ":(9330|9331)\b" || true

echo ""
echo "[完成] Step 4. 接下来可用:"
echo "  bash scripts/check.sh                # 一键看 进程/端口/日志尾/钱包文件"
echo "  tail -f logs/discreted.log           # 实时日志 (出块会有打印)"
echo "  bash scripts/stop.sh                 # 优雅停止"
