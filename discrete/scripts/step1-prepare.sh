#!/usr/bin/env bash
# Step 1: 准备目录结构 + 检查二进制 + 根据本机硬件给出挖矿线程档位建议
# 参考: https://docs.discrete.cash/#/operators/node-operation
# 目的:
#   1) 创建 data/wallet/logs/run/config/downloads 目录
#   2) 确认 bin/discreted / bin/simplewallet 存在可执行
#   3) 探测本机 CPU / 内存 / 温度, 给出 Discrete 挖矿的线程建议
#      (DiscretePower 是 ML-DSA-65 签名 + yespower-discrete, 都是整数重算力,
#       SMT 超线程收益 5~15%, 因此线程数建议 <= 物理核数)
# 预期结果:
#   - 列出硬件信息
#   - 给出 3 档建议 (保守 / 推荐 / 激进)
#   - Step 4 启动挖矿时 默认线程数 = 「物理核数」(推荐档)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

cd "${PROJECT_DIR}"
mkdir -p bin data wallet logs run config downloads
echo "[OK] 目录已创建: data/ wallet/ logs/ run/ config/ downloads/"

echo ""
echo "检查二进制文件 bin/:"
ls -la bin/

echo ""
if [[ -x bin/discreted ]]; then
  echo "[OK] discreted 存在"
else
  echo "[缺失] bin/discreted 未找到 —— 从 https://github.com/discretecoin/discrete/releases/tag/v.0.9.5 下载"
  echo "       解压后把 discreted / simplewallet 两个可执行文件放到 $(pwd)/bin/"
  exit 1
fi

if [[ -x bin/simplewallet ]]; then
  echo "[OK] simplewallet 存在"
else
  echo "[缺失] bin/simplewallet 未找到"
  exit 1
fi

echo ""
echo "╔══════════════════════════════════════════════════════════════════╗"
echo "║                    本机硬件 & Discrete 挖矿建议                   ║"
echo "╚══════════════════════════════════════════════════════════════════╝"

# --- CPU ---
NPROC="$(nproc)"
PHYSICAL_PKGS="$(grep -c '^physical id' /proc/cpuinfo 2>/dev/null || echo 1)"
[[ "${PHYSICAL_PKGS:-0}" -lt 1 ]] && PHYSICAL_PKGS=1
CORES_PER_PKG="$(grep '^cpu cores' /proc/cpuinfo | head -1 | awk -F: '{print $2}' | xargs)"
[[ -z "${CORES_PER_PKG}" ]] && CORES_PER_PKG="${NPROC}"
PHYSICAL_CORES=$(( PHYSICAL_PKGS * CORES_PER_PKG ))
[[ "${PHYSICAL_CORES}" -lt 1 ]] && PHYSICAL_CORES=1
CPU_MODEL="$(grep '^model name' /proc/cpuinfo | head -1 | awk -F: '{print $2}' | xargs)"
echo "  CPU:              ${CPU_MODEL}"
echo "    物理 CPU 颗数:  ${PHYSICAL_PKGS}"
echo "    每颗核心数:     ${CORES_PER_PKG}"
echo "    物理核总数:     ${PHYSICAL_CORES}   (推荐挖矿线程上限, SMT 增益有限)"
echo "    逻辑核(SMT):    ${NPROC}"

# --- Memory ---
MEM_GB="$(free -g 2>/dev/null | awk '/^Mem:/{print $2}')"
[[ -z "${MEM_GB}" ]] && MEM_GB="$(awk '/MemTotal/{printf "%.0f", $2/1024/1024}' /proc/meminfo)"
echo "  内存总容量:       ${MEM_GB} GB    (DiscretePower 每线程仅 ~16 MB, 内存不是瓶颈)"

# --- Disk (project dir partition) ---
DISK_SIZE="$(df -h . | awk 'NR==2{print $2}')"
DISK_USED="$(df -h . | awk 'NR==2{print $3}')"
DISK_AVAIL="$(df -h . | awk 'NR==2{print $4}')"
DISK_USE_PCT="$(df -h . | awk 'NR==2{print $5}')"
echo "  项目所在分区:     总 ${DISK_SIZE}  | 已用 ${DISK_USED} (${DISK_USE_PCT}) | 剩余 ${DISK_AVAIL}"

# --- Temperature ---
HAS_TEMP=0
CPU_TEMP_TCTL="N/A"
NVME_TEMP="N/A"
if command -v sensors >/dev/null 2>&1; then
  TCTL="$(sensors 2>/dev/null | awk -F'[:+°]' '/^Tctl/{gsub(/ /,"",$3);print $3;exit}')"
  [[ -n "${TCTL}" ]] && { CPU_TEMP_TCTL="${TCTL}°C"; HAS_TEMP=1; }
  NVME="$(sensors 2>/dev/null | awk -F'[:+°]' '/^Composite/{gsub(/ /,"",$3);print $3;exit}')"
  [[ -n "${NVME}" ]] && NVME_TEMP="${NVME}°C"
fi
echo "  CPU Tctl 温度:    ${CPU_TEMP_TCTL}   (< 85°C 安全; >95°C 需降线程)"
echo "  NVMe 温度:        ${NVME_TEMP}"

# --- Load avg (目前忙不忙) ---
LOAD1="$(cut -d' ' -f1 /proc/loadavg)"
LOAD5="$(cut -d' ' -f2 /proc/loadavg)"
echo "  负载 loadavg:     1min=${LOAD1}  5min=${LOAD5}"

echo ""
echo "──────────────────── 挖矿线程档位建议 ────────────────────"
# 保守 = 物理核 - 4 (给其它服务留余量), 至少 1
CONSERVATIVE=$(( PHYSICAL_CORES - 4 ))
[[ "${CONSERVATIVE}" -lt 1 ]] && CONSERVATIVE=1
# 推荐 = 物理核数
RECOMMENDED="${PHYSICAL_CORES}"
# 激进 = 物理核 + 50% SMT (不超过 NPROC)
AGGRESSIVE=$(( PHYSICAL_CORES + PHYSICAL_CORES / 2 ))
[[ "${AGGRESSIVE}" -gt "${NPROC}" ]] && AGGRESSIVE="${NPROC}"
echo "  🟡 保守档:  ${CONSERVATIVE} 线程   (= 物理核 - 4)   你还想跑 Docker/AI 服务时"
echo "  🟢 推荐档:  ${RECOMMENDED} 线程   (= 物理核数)     ✅ 性价比最高 (整数算力, SMT 增益低)"
echo "  🔴 激进档:  ${AGGRESSIVE} 线程   (= 物理核 + SMT)  发热多 收益少, 仅完全空机建议"
echo ""
echo "  Step 4 默认使用推荐档 ${RECOMMENDED} 线程。 手动覆盖示例:"
echo "      bash scripts/step4-start-mining.sh ${CONSERVATIVE}    (保守)"
echo "      bash scripts/step4-start-mining.sh ${RECOMMENDED}    (推荐)"
echo "      bash scripts/step4-start-mining.sh ${AGGRESSIVE}    (激进)"

echo ""
echo "[完成] Step 1 通过. 进入 Step 2: bash scripts/step2-start-node.sh"
