#!/bin/bash
set -euo pipefail

# --- 颜色定义 ---
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}=== LeHome Challenge 2026 安装脚本 (Part 2: 官方构建与下载) ===${NC}"

# --- 补充：确保当前脚本能找到 uv 工具 ---
export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"

# --- 0. 定位目录 ---
echo -e "${GREEN}>>> 定位项目目录...${NC}"
# 兼容你在 /root/data 下运行，或者已经在项目目录下的情况
if [ -d "lehome-challenge" ]; then
    cd lehome-challenge
elif [ ! -f "pyproject.toml" ]; then
    TARGET_DIR="/root/data/lehome-challenge"
    if [ -d "$TARGET_DIR" ]; then
        cd "$TARGET_DIR"
    else
        echo -e "${RED}错误：找不到 lehome-challenge 目录，请先运行 Part 1 或者确认当前路径。${NC}"
        exit 1
    fi
fi
PROJECT_DIR="$(pwd)"

# =================================================================
# --- 1. 严格执行官方文档 (Official Docs Steps) ---
# =================================================================
echo -e "${GREEN}>>> 开始执行官方 IsaacLab 安装与数据集下载...${NC}"

# 激活环境
source .venv/bin/activate

# 编译 IsaacLab (官方指令)
./third_party/IsaacLab/isaaclab.sh -i none

# Install LeHome Package (官方指令)
uv pip install -e ./source/lehome

# Download Assets (官方指令)
hf download lehome/asset_challenge --repo-type dataset --local-dir Assets

# Download Example Dataset (官方指令 - 合并版)
hf download lehome/dataset_challenge_merged --repo-type dataset --local-dir Datasets/example

# Download Dataset with depth information (官方指令 - 完整独立版)
hf download lehome/dataset_challenge --repo-type dataset --local-dir Datasets/example
# =================================================================

# --- 2. 结束指引 ---
echo -e "${BLUE}==========================================${NC}"
echo -e "${GREEN}全部安装与下载结束！${NC}"
echo -e "项目路径: ${PROJECT_DIR}"
echo -e "手动激活环境命令: ${YELLOW}cd ${PROJECT_DIR} && source .venv/bin/activate${NC}"
echo -e "${BLUE}==========================================${NC}"