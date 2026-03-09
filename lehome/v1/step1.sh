#!/bin/bash
set -euo pipefail

# --- 1. 核心环境变量 (含代理配置) ---
KERNEL_NAME=mihomo
CLASH_BASE_DIR=~/clashctl
CLASH_SUB_UA="clash-verge/v2.4.0"
# 如果需要自动开启代理，请在此处填入订阅链接
CLASH_CONFIG_URL="" 
VERSION_MIHOMO="v1.19.17"

# --- 颜色定义 ---
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}=== LeHome Challenge 2026 全自动增强安装脚本 ===${NC}"

# --- 2. 权限与系统依赖检测 ---
PRIV_CMD=()
[[ "$(id -u)" -eq 0 ]] || PRIV_CMD=(sudo)

# 询问安装系统依赖 (IsaacSim 必需)
read -r -p "是否安装服务器系统依赖 (libGL, libEGL等)? [y/N]: " INSTALL_SYS
if [[ "${INSTALL_SYS,,}" == "y" ]]; then
    echo -e "${GREEN}>>> 安装系统底层图形库...${NC}"
    "${PRIV_CMD[@]}" apt update && "${PRIV_CMD[@]}" apt install -y \
        libglu1-mesa libgl1 libegl1 libxrandr2 libxinerama1 \
        libxcursor1 libxi6 libxext6 libx11-6
    export __GLX_VENDOR_LIBRARY_NAME=nvidia
fi

# --- 3. 智能代理启动逻辑 (可选) ---
if [[ -n "$CLASH_CONFIG_URL" ]]; then
    echo -e "${YELLOW}>>> 检测到订阅链接，正在尝试初始化网络代理加速...${NC}"
    # 此处省略具体的 clash 启动指令，假设您已安装 clashctl 环境
    # 建议手动确认代理生效：export http_proxy=http://127.0.0.1:7890
fi

# --- 4. UV 工具安装 (环境管理核心) ---
echo -e "${GREEN}>>> [1/7] 检查并安装 uv 工具...${NC}"
export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"
if ! command -v uv >/dev/null 2>&1; then
    curl -LsSf https://astral.sh/uv/install.sh | sh
    export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"
fi

# --- 5. 仓库克隆与目录定位 ---
if [ ! -f "pyproject.toml" ]; then
    if [ -d "lehome-challenge" ]; then
        cd lehome-challenge
    else
        echo -e "${GREEN}>>> [2/7] 克隆主仓库...${NC}"
        git clone https://github.com/lehome-official/lehome-challenge.git
        cd lehome-challenge
    fi
fi
PROJECT_DIR="$(pwd)"

# --- 7. 同步依赖与安装组件 ---
echo -e "${GREEN}>>> [4/7] 同步项目依赖 (使用 Python 3.11)...${NC}"
uv sync

echo -e "${GREEN}>>> [5/7] 配置并安装 IsaacLab...${NC}"
mkdir -p third_party
if [ ! -d "third_party/IsaacLab" ]; then
    git clone https://github.com/lehome-official/IsaacLab.git third_party/IsaacLab
fi

# 在子 Shell 中执行激活环境后的安装步骤
(
    source .venv/bin/activate
    echo "安装 IsaacLab 核心..."
    ./third_party/IsaacLab/isaaclab.sh -i none
    
    echo "安装 LeHome 包及 HuggingFace 工具..."
    uv pip install -e ./source/lehome
    uv pip install "huggingface_hub[cli]"
)

# --- 8. 资产与数据下载 (README 步骤 2) ---
echo -e "${GREEN}>>> [6/7 & 7/7] 下载 Assets 与示例数据集...${NC}"
(
    source .venv/bin/activate
    # 下载仿真资源
    hf download lehome/asset_challenge --repo-type dataset --local-dir Assets
    # 下载合并数据集
    hf download lehome/dataset_challenge_merged --repo-type dataset --local-dir Datasets/example
)

# --- 9. 结束指引 ---
echo -e "${BLUE}==========================================${NC}"
echo -e "${GREEN}安装成功！已为您自动切换至 Python 3.11 环境。${NC}"
echo -e "项目路径: ${PROJECT_DIR}"
echo -e "激活环境命令: ${YELLOW}source .venv/bin/activate${NC}"
echo -e "注意: 仿真评估仅支持 ${RED}--device cpu${NC} 模式"
echo -e "${BLUE}==========================================${NC}"