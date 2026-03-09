#!/bin/bash
set -euo pipefail

# --- 颜色定义 (让终端不再枯燥) ---
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

echo -e "${PURPLE}==================================================${NC}"
echo -e "${PURPLE}🌐  Clash-for-Linux 自动化部署工具 (学术加速增强版)${NC}"
echo -e "${PURPLE}==================================================${NC}"

# --- 1. 开启学术加速 ---
echo -e "${BLUE}📡 [1/5] 正在激活学术加速通道...${NC}"
if [ -f "/public/bin/network_accelerate" ]; then
    source /public/bin/network_accelerate
    echo -e "${GREEN}✅ 加速已开启，正在直连 GitHub...${NC}"
else
    echo -e "${YELLOW}⚠️  提示: 未找到加速脚本，将尝试普通连接。${NC}"
fi

# --- 2. 克隆项目仓库 ---
echo -e "${BLUE}🚚 [2/5] 正在拉取 clash-for-linux-install 仓库...${NC}"
# 彻底清理旧目录，确保版本最干净
rm -rf clash-for-linux-install
git clone --branch master --depth 1 https://github.com/nelvko/clash-for-linux-install.git

if [ ! -d "clash-for-linux-install" ]; then
    echo -e "${RED}❌ 错误: 仓库拉取失败，请检查网络连接！${NC}"
    exit 1
fi
cd clash-for-linux-install

# --- 3. 环境配置与去代理化 ---
echo -e "${BLUE}⚙️  [3/5] 正在优化安装配置 (移除 gh-proxy)...${NC}"

# 移除安装脚本中的 gh-proxy 代理（既然开了学术加速，直连才是王道）
# 使用 | 作为分隔符防止 URL 冲突
sed -i 's|https://gh-proxy.org||g' install.sh 2>/dev/null || true

echo -e "${BLUE}📝 [3/5] 正在注入自定义 .env 订阅配置...${NC}"
cat <<EOF > .env
# 安装内核 可选：mihomo、clash
KERNEL_NAME=mihomo

# 安装路径
CLASH_BASE_DIR=~/clashctl

# 机场订阅地址
CLASH_CONFIG_URL=https://dash.knjc.cfd/api/v1/client/subscribe?token=a3bf795ae9fbca04056b2d4e74a38ac0

# 下载订阅时的 UserAgent
CLASH_SUB_UA=clash-verge/v2.4.0

# 软件版本号锁定
VERSION_MIHOMO=v1.19.17
VERSION_YQ=v4.49.2
VERSION_SUBCONVERTER=v0.9.0

# 控制面板相关
URL_CLASH_UI=http://board.zash.run.place
ZIP_UI=resources/zip/dist.zip
URL_GH_PROXY=
EOF
echo -e "${GREEN}✅ .env 配置写入完成。${NC}"

# --- 4. 执行正式安装 ---
echo -e "${YELLOW}🚀 [4/5] 正在启动正式安装程序，请稍候...${NC}"
echo -e "${YELLOW}------------------------------------------------${NC}"
bash install.sh
echo -e "${YELLOW}------------------------------------------------${NC}"

# --- 5. 关闭学术加速 ---
echo -e "${BLUE}🧹 [5/5] 安装完毕，正在清理学术加速状态...${NC}"
if [ -f "/public/bin/network_accelerate_stop" ]; then
    source /public/bin/network_accelerate_stop
    echo -e "${GREEN}✅ 加速已关闭，回归标准网络环境。${NC}"
fi

# --- 最终指引 ---
echo -e "${PURPLE}==================================================${NC}"
echo -e "${GREEN}🎉 代理部署大功告成！${NC}"
echo -e "${BLUE}🌐 管理面板：${YELLOW}http://board.zash.run.place${NC}"
echo -e "${BLUE}🔌 本地端口：${YELLOW}7890${NC}"
echo -e "${BLUE}📂 安装目录：${YELLOW}~/clashctl${NC}"
echo -e "${PURPLE}==================================================${NC}"
echo -e "${YELLOW}💡 提示: 记得在终端输入 'proxy_on' (如果安装脚本提供了此别名) 开启代理。${NC}"