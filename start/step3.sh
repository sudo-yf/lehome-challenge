#!/bin/bash
set -euo pipefail

# --- 颜色定义 ---
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}==================================================${NC}"
echo -e "${BLUE}🚀 LeHome Challenge 2026 全能环境配置脚本${NC}"
echo -e "${BLUE}==================================================${NC}"

# --- 1. 处理 data 盘软链接 (解决 UV 跨盘硬链接警告) ---
echo -e "${GREEN}🔗 [1/4] 正在配置 data 盘缓存软链接...${NC}"
mkdir -p /root/data/.uv_cache
mkdir -p ~/.cache
rm -rf ~/.cache/uv
ln -sf /root/data/.uv_cache ~/.cache/uv
echo -e "✅ 软链接已建立: ~/.cache/uv -> /root/data/.uv_cache"

# --- 2. 写入 .bashrc 自动化逻辑 ---
echo -e "${GREEN}📝 [2/4] 正在配置 .bashrc 自动化脚本与快捷命令...${NC}"

# 清理旧配置防止重复
sed -i '/# --- LeHome 环境配置 ---/,/ # --- End LeHome ---/d' ~/.bashrc

cat << 'EOF' >> ~/.bashrc
# --- LeHome 环境配置 ---
export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"

# 自动激活环境逻辑 (静默版)
cd_activate_venv() {
    builtin cd "$@" || return
    if [ -f ".venv/bin/activate" ]; then
        if [[ "${VIRTUAL_ENV:-}" != "$(pwd)/.venv" ]]; then
            source .venv/bin/activate
        fi
    fi
}
alias cd='cd_activate_venv'

# 快捷命令
alias go='cd /root/data/lehome-challenge && source .venv/bin/activate'
alias save='bash /root/data/lehome-challenge/start/step_git.sh'

# 登录时如果在项目内，自动激活
if [ -f ".venv/bin/activate" ]; then source .venv/bin/activate; fi
# --- End LeHome ---
EOF

# 立即在当前进程刷新路径
export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"

# --- 3. IsaacSim 授权与路径协调 ---
echo -e "${GREEN}🛡️  [3/4] 准备进行 IsaacSim 授权...${NC}"

# 确保在项目目录下执行后续 python 命令
if [ -d "/root/data/lehome-challenge" ]; then
    cd /root/data/lehome-challenge
fi

if [ ! -f ".venv/bin/activate" ]; then
    echo -e "${RED}❌ 错误: 未找到 .venv 文件夹。请确认已在 /root/data/lehome-challenge 运行过 uv sync。${NC}"
    exit 1
fi

source .venv/bin/activate

echo -e "${YELLOW}====================================================${NC}"
echo -e "${YELLOW}提示：下方将出现 NVIDIA 官方授权协议。${NC}"
echo -e "${YELLOW}请在看到 'Do you accept the EULA? (Yes/No):' 时，手动输入 Yes 并回车。${NC}"
echo -e "${YELLOW}====================================================${NC}"

# 触发授权
python -c "import isaacsim; print('\n${GREEN}授权成功！正在提取路径信息...${NC}')"

# 提取物理路径
ISAACSIM_PKG_PATH=$(python -c "import isaacsim, os; print(os.path.dirname(isaacsim.__file__))")

if [ -z "$ISAACSIM_PKG_PATH" ]; then
    echo -e "${RED}❌ 错误: 授权已通过但未能提取到路径。${NC}"
    exit 1
fi

echo -e "${GREEN}检测到物理路径: $ISAACSIM_PKG_PATH${NC}"

# --- 4. 建立 IsaacLab 内部链接 ---
echo -e "${GREEN}🔗 [4/4] 正在建立 IsaacLab 软链接...${NC}"
LINK_TARGET="third_party/IsaacLab/_isaac_sim"
mkdir -p third_party/IsaacLab
rm -rf "$LINK_TARGET"
ln -sf "$ISAACSIM_PKG_PATH" "$LINK_TARGET"

# --- 5. 最终验证与结束指引 ---
if [ -L "$LINK_TARGET" ] && [ -e "$LINK_TARGET" ]; then
    echo -e "${BLUE}==================================================${NC}"
    echo -e "${GREEN}🎉 恭喜！所有环境优化与路径授权已完成。${NC}"
    echo -e "👉 请手动执行一次: ${YELLOW}source ~/.bashrc${NC}"
    echo -e "👉 以后直接输入: ${YELLOW}go${NC} 即可秒进项目环境"
    echo -e "👉 备份代码请输入: ${YELLOW}save 版本号${NC}"
    echo -e "${BLUE}==================================================${NC}"
else
    echo -e "${RED}❌ 警告: 最终链接校验失败，请检查目录权限。${NC}"
    exit 1
fi
