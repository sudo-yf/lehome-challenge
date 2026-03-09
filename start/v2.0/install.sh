#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

usage() {
    cat <<'USAGE'
Usage: bash start/v2.0/install.sh [--install-system-libs]

- --install-system-libs  安装 IsaacSim 需要的系统图形库
USAGE
}

INSTALL_SYSTEM_LIBS=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --install-system-libs)
            INSTALL_SYSTEM_LIBS=1
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            die "❌ 不支持的参数: $1"
            ;;
    esac
    shift
done

ensure_repo_root
ensure_uv
link_uv_cache

if [[ $INSTALL_SYSTEM_LIBS -eq 1 ]]; then
    install_system_libs
else
    warn "⚠️ 未安装系统图形库；若后续 IsaacSim/FFmpeg 报错，请重新执行并带上 --install-system-libs"
fi

log "📦 开始同步 Python 依赖..."
uv sync --locked
ok "✅ uv sync --locked 完成"

clone_isaaclab_if_missing
activate_venv

log "🧠 安装 IsaacLab..."
./third_party/IsaacLab/isaaclab.sh -i none

log "🧵 安装 LeHome 与 HuggingFace CLI..."
uv pip install -e ./source/lehome
uv pip install "huggingface_hub[cli]"

log "🔍 校验核心导入..."
check_imports torch torchvision lerobot isaacsim lehome isaaclab isaaclab_tasks isaaclab_rl isaaclab_mimic isaaclab_assets isaaclab_contrib
ok "✅ 核心环境安装完成"
