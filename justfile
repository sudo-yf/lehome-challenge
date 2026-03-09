# 强制使用 bash 并开启严格模式
set shell := ["bash", "-uc"]

# 默认列出所有可用命令
default:
    @just --list

# --- 核心流程 (全部指向 start 文件夹) ---

# 开启 VPN 代理
vpn:
    bash start/step_vpn.sh

# 执行 Step 1: 基础安装
s1:
    bash start/step1.sh

# 执行 Step 2: 授权与软链接
s2:
    bash start/step2.sh

# 执行 Step 3: 运行仿真验证
s3:
    bash start/step3.sh

# 备份代码到 GitHub (用法: just save 10)
# 对应原本的 step_git.sh，支持传入版本号参数
save version:
    bash start/step_git.sh {{version}}

# 一键全自动配置 (按顺序跑完 1, 2, 3)
setup:
    just s1
    just s2
    just s3
