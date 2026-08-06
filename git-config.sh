#!/usr/bin/env bash
# =============================================================================
# git-config.sh — 引导式配置项目级 Git 信息
# =============================================================================
# 交互式引导
#
# 用法:
#   cd /root/deAI && bash git-config.sh
#
# =============================================================================

set -euo pipefail

# ---- 定位项目根目录 ----
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

# ---- 检查是否在 git 仓库内 ----
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "❌ 当前目录不是 git 仓库: ${SCRIPT_DIR}"
  exit 1
fi

echo "=============================================="
echo "  项目级 Git 身份配置"
echo "  仓库: ${SCRIPT_DIR}"
echo "=============================================="
echo

# ---- 当前已有配置 ----
CUR_NAME=$(git config user.name || true)
CUR_EMAIL=$(git config user.email || true)
[ -n "$CUR_NAME" ]  && echo "当前 user.name : $CUR_NAME"
[ -n "$CUR_EMAIL" ] && echo "当前 user.email: $CUR_EMAIL"
echo

# ---- 引导输入 user.name ----
echo "1) 请输入提交者姓名 (user.name):"
echo "   提示: 将显示在你 GitHub 的 commit 记录里"
if [ -n "$CUR_NAME" ]; then
  read -r -p "    [回车使用当前值 ${CUR_NAME}]: " NAME
  NAME="${NAME:-$CUR_NAME}"
else
  read -r -p "   > " NAME
fi
[ -z "$NAME" ] && echo "❌ 姓名不能为空" && exit 1

echo
echo "2) 请输入提交者邮箱 (user.email):"
echo "   隐私提示: 若要隐藏真实邮箱，GitHub 隐私邮箱格式为 <ID>@users.noreply.github.com"
if [ -n "$CUR_EMAIL" ]; then
  read -r -p "    [回车使用当前值 ${CUR_EMAIL}]: " EMAIL
  EMAIL="${EMAIL:-$CUR_EMAIL}"
else
  read -r -p "   > " EMAIL
fi
[ -z "$EMAIL" ] && echo "❌ 邮箱不能为空" && exit 1

echo
echo "3) 确认信息:"
echo "   user.name : $NAME"
echo "   user.email: $EMAIL"
read -r -p "   确认写入？(y/N): " CONFIRM
case "${CONFIRM,,}" in
  y|yes) ;;
  *) echo "已取消，未写入。" ; exit 0 ;;
esac

# ---- 写入项目级配置 ----
git config user.name "$NAME"
git config user.email "$EMAIL"

echo
echo "=============================================="
echo "✅ 已写入项目级(local)配置："
echo "   user.name : $(git config user.name)"
echo "   user.email: $(git config user.email)"
echo "   配置来源  : $(git config --show-origin user.name)"
echo "=============================================="
echo
echo "下一步常用命令："
echo "  查看远程地址 : git remote -v"
echo "  推送代码      : git push -u <remote> <branch>"
