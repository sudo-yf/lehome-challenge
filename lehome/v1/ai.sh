#!/bin/bash

# 颜色输出配置
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== 🚀 开始全自动配置 AI 编程环境 ===${NC}"

# ==========================================
# 1. 检查并安装 Node.js 环境 (使用 Conda)
# ==========================================
echo -e "\n${YELLOW}[1/4] 检查基础环境 (Node.js & npm)...${NC}"
if ! command -v node &> /dev/null; then
    echo -e "未检测到 Node.js，正在使用 Conda 自动安装 Node.js 20..."
    if command -v conda &> /dev/null; then
        conda install -c conda-forge nodejs=20 -y
    else
        echo -e "${RED}错误: 未检测到 Conda 环境。请先安装 Conda。${NC}"
        exit 1
    fi
else
    echo -e "Node.js 已安装: ${GREEN}$(node -v)${NC}"
fi

# ==========================================
# 2. 配置 npm 国内镜像源 (防止下载卡死)
# ==========================================
echo -e "\n${YELLOW}[2/4] 配置 npm 国内镜像源...${NC}"
npm config set registry https://registry.npmmirror.com
echo -e "当前 npm 源已设置为: ${GREEN}$(npm config get registry)${NC}"

# ==========================================
# 3. 安装核心 AI 工具链
# ==========================================
echo -e "\n${YELLOW}[3/4] 开始安装 AI 工具链 (Claude, Codex, ZCF, Happy Coder)...${NC}"
npm install -g @anthropic-ai/claude-code
npm install -g @openai/codex
npm install -g zcf
npm install -g happy-coder
echo -e "${GREEN}AI 工具链安装完成！${NC}"

# ==========================================
# 4. 可选配置：Tmux + Cron 心跳保活机制
# ==========================================
echo -e "\n${YELLOW}[4/4] 高级选项：Agent 心跳保活机制${NC}"
echo "开启此功能后，系统会每小时自动向后台运行的 Agent 发送状态汇报指令，防止其休眠或断开。"

read -p "是否需要配置 'Tmux + 定时心跳' 保活机制? (y/n): " config_heartbeat

if [[ "$config_heartbeat" =~ ^[Yy]$ ]]; then
    echo -e "\n${GREEN}正在配置保活机制...${NC}"

    # 检查并安装 tmux
    if ! command -v tmux &> /dev/null; then
        echo "未检测到 tmux，正在使用 Conda 安装..."
        conda install -c conda-forge tmux -y
    fi

    # 获取当前目录，并在当前目录下生成 heartbeat.sh
    HEARTBEAT_FILE="$PWD/heartbeat.sh"
    
    cat << 'EOF' > "$HEARTBEAT_FILE"
#!/bin/bash
# 这是一个自动生成的心跳脚本
# 它会向名为 ai_session 的 tmux 会话发送一段文本，并模拟按下回车 (C-m)
tmux send-keys -t ai_session "进行常规的代码检查和状态汇报" C-m
EOF
    
    # 赋予心跳脚本执行权限
    chmod +x "$HEARTBEAT_FILE"
    echo -e "已生成心跳脚本: ${GREEN}$HEARTBEAT_FILE${NC}"

    # 配置 Crontab 定时任务 (每小时的第 0 分钟执行)
    # 先清理可能存在的旧任务，再添加新任务，防止重复添加
    (crontab -l 2>/dev/null | grep -v "$HEARTBEAT_FILE"; echo "0 * * * * $HEARTBEAT_FILE") | crontab -
    
    echo -e "${GREEN}Crontab 定时任务配置成功！(每小时触发一次)${NC}"
    
    echo -e "\n${YELLOW}【💡 心跳机制使用说明】${NC}"
    echo -e "1. 输入 ${GREEN}tmux new -s ai_session${NC} 启动一个新的后台会话。"
    echo -e "2. 在该会话中启动你的 Agent (例如输入 ${GREEN}claude${NC} 或 ${GREEN}codex${NC})。"
    echo -e "3. 键盘按下 ${YELLOW}Ctrl+B 然后按 D${NC}，可以将其挂在后台运行。"
    echo -e "4. 系统会自动每小时唤醒它一次。想回去看它时，输入 ${GREEN}tmux attach -t ai_session${NC} 即可。"
else
    echo -e "已跳过心跳保活机制的配置。"
fi

echo -e "\n${GREEN}=== 🎉 所有环境配置完毕，祝你 Coding 愉快！ ===${NC}"