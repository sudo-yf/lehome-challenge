#!/bin/bash
set -euo pipefail

# === 配置区 ===
TARGET_DIR="/root/data/lehome-challenge"
GITHUB_USER="sudo-yf"
GITHUB_EMAIL="$GITHUB_USER@users.noreply.github.com"
VERSION_NUM="${1:-}"

if [ -z "$VERSION_NUM" ]; then
    echo "❌ 错误: 忘记写版本号啦！"
    echo "💡 正确用法: bash git.sh 1"
    exit 1
fi

VERSION="v$VERSION_NUM"
COMMIT_MSG="Auto save version $VERSION"

echo "=================================================="
echo "🛡️  开始防夺舍检测与一键备份 (目标版本: $VERSION)"
echo "=================================================="

# --- 0. 自动定位目录与激活环境 ---
echo "📂 [0/5] 定位目录并激活环境..."
if [ ! -d "$TARGET_DIR" ]; then
    echo "❌ 错误: 找不到目标目录 $TARGET_DIR"
    exit 1
fi
cd "$TARGET_DIR"

if [ -f ".venv/bin/activate" ]; then
    source .venv/bin/activate
    echo "✅ 虚拟环境已激活"
else
    echo "⚠️ 警告: 未找到 .venv，将使用系统环境继续"
fi

# --- 1. 检查并配置 Git 身份 ---
echo "👤 [1/5] 检查 Git 身份配置..."
if [ -z "$(git config user.name)" ]; then
    git config --global user.name "$GITHUB_USER"
    git config --global user.email "$GITHUB_EMAIL"
    echo "✅ 身份已设为: $GITHUB_USER"
else
    echo "✅ 身份已确认: $(git config user.name)"
fi

# --- 2. 防夺舍检测 ---
echo "🔍 [2/5] 检查仓库归属..."
MAIN_ORIGIN=$(git remote get-url origin 2>/dev/null || echo "")
if [[ "$MAIN_ORIGIN" == *"lehome-official"* ]]; then
    echo "⚠️ 发现仓库被官方占用，正在为你执行换源..."
    git remote set-url origin "https://github.com/$GITHUB_USER/lehome-challenge.git"
    git remote add upstream "https://github.com/lehome-official/lehome-challenge.git" 2>/dev/null || true
else
    echo "✅ 仓库归属正常"
fi

# --- 3. 自动提交变动 ---
echo "🚀 [3/5] 处理代码变动..."
git add .
# 尝试提交，如果没变动则不报错
git commit -m "$COMMIT_MSG" || echo "💤 工作区无新变动，跳过 commit 阶段..."

# --- 4. 更新版本标签 ---
echo "🏷️  [4/5] 更新版本标签..."
git tag -d "$VERSION" 2>/dev/null || true
git tag "$VERSION"

# --- 5. 推送 ---
echo "📤 [5/5] 推送到 GitHub ($GITHUB_USER)..."
# 推送当前所在的分支
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
git push origin "$CURRENT_BRANCH"
git push origin "$VERSION" -f

echo "=================================================="
echo "🎉 完美收工！$VERSION 已包含最新环境状态并同步！"