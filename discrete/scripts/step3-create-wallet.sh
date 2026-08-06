#!/usr/bin/env bash
# Step 3: 创建挖矿钱包 (必须交互式输入密码 2 次)
# 参考: https://docs.discrete.cash/#/wallets/wallet-scope
#   相关 CLI: simplewallet --generate-new-wallet <walletfile>
# 目的: 生成 miner.wallet (主文件) + miner.wallet.keys (密钥文件) + 显示/保存 助记词种子
# 预期结果: wallet/ 目录下出现 miner.wallet / miner.wallet.keys;
#           脚本提示保存 seed 短语到 wallet/miner-seed.txt;
#           ⚠️ seed 是恢复资金的唯一方式, 必须离线备份
#
# 关键说明:
#   - 本脚本会进入交互模式.  simplewallet 会要求输入密码两次.
#   - 钱包创建成功后会进入 simplewallet> 提示符, 依次执行:
#       print_seed        # 手动复制输出的 24/25 词 seed
#       address           # 记录钱包地址
#       exit              # 退出
#   - 或者看到 simplewallet> 后直接在里面做:
#       print_seed > wallet/miner-seed.txt
#       exit
#     也能把 seed 保存下来

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${PROJECT_DIR}"

BIN="$(pwd)/bin/simplewallet"
WALLET="$(pwd)/wallet/miner.wallet"
SEED="$(pwd)/wallet/miner-seed.txt"

mkdir -p wallet

if [[ ! -x "${BIN}" ]]; then
  echo "[错误] simplewallet 不存在, 先执行 scripts/step1-prepare.sh"
  exit 1
fi

# 确保 RPC 已起来 (simplewallet --daemon-address 需要连接 RPC)
if ! (ss -tlnp 2>/dev/null || netstat -tlnp 2>/dev/null) | grep -q "127.0.0.1:9331"; then
  echo "[错误] 未检测到 127.0.0.1:9331 RPC —— 先运行 scripts/step2-start-node.sh"
  exit 1
fi

if [[ -f "${WALLET}" ]]; then
  echo "[跳过] ${WALLET} 已存在; 如需重建先删除它: rm wallet/miner.wallet*"
  exit 0
fi

cat <<'EOF'
============================================================================
  创建钱包 —— 进入交互模式, 你需要依次:

  1. simplewallet 会连续两次提示输入钱包密码 (输入时不显示)
     请设置一个强密码, 两次输入一致后按回车
     ⚠️ 密码忘记无法恢复, 请写下来

  2. 进入提示符 simplewallet> 后, 按顺序输入:

        print_seed
        👉 把屏幕输出的 seed 短语 (24/25 个词) 手工保存到离线位置
        👉 也可以执行:  print_seed > wallet/miner-seed.txt   直接写文件

        address
        👉 记下显示的钱包地址

        exit

  3. 本脚本仅启动 simplewallet, 后续输入由你手动完成.
============================================================================
EOF

read -r -s -p "按回车进入 simplewallet 交互界面..." _
echo ""

exec "${BIN}" \
  --generate-new-wallet "${WALLET}" \
  --mnemonic-file "${SEED}" \
  --daemon-address "127.0.0.1:9331"
