#!/usr/bin/env bash
set -euo pipefail

V2_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd -- "$V2_DIR/../.." && pwd)"

BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log() {
    echo -e "${BLUE}$*${NC}"
}

ok() {
    echo -e "${GREEN}$*${NC}"
}

warn() {
    echo -e "${YELLOW}$*${NC}"
}

die() {
    echo -e "${RED}$*${NC}" >&2
    exit 1
}

project_root() {
    echo "$PROJECT_ROOT"
}

ensure_repo_root() {
    [[ -f "$PROJECT_ROOT/pyproject.toml" ]] || die "❌ 找不到项目根目录: $PROJECT_ROOT"
    cd "$PROJECT_ROOT"
}

ensure_path() {
    export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"
}

ensure_uv() {
    ensure_path
    if ! command -v uv >/dev/null 2>&1; then
        log "🔧 未检测到 uv，开始安装..."
        curl -LsSf https://astral.sh/uv/install.sh | sh
        ensure_path
    fi
    ok "✅ uv 已就绪: $(command -v uv)"
}

link_uv_cache() {
    local target="/root/data/.uv_cache"
    local link_path="$HOME/.cache/uv"

    mkdir -p "$target" "$HOME/.cache"

    if [[ -L "$link_path" ]]; then
        local current
        current="$(readlink -f "$link_path")"
        if [[ "$current" == "$target" ]]; then
            ok "✅ UV 缓存软链接已存在: $link_path -> $target"
            return 0
        fi
        rm -f "$link_path"
    elif [[ -e "$link_path" ]]; then
        die "❌ $link_path 已存在且不是软链接，请先手动处理后再执行。"
    fi

    ln -s "$target" "$link_path"
    ok "✅ 已建立缓存软链接: $link_path -> $target"
}

install_system_libs() {
    local priv_cmd=()
    [[ "$(id -u)" -eq 0 ]] || priv_cmd=(sudo)

    log "🧱 安装 IsaacSim 所需系统库..."
    "${priv_cmd[@]}" apt update
    "${priv_cmd[@]}" apt install -y \
        libglu1-mesa \
        libgl1 \
        libegl1 \
        libxrandr2 \
        libxinerama1 \
        libxcursor1 \
        libxi6 \
        libxext6 \
        libx11-6
    export __GLX_VENDOR_LIBRARY_NAME=nvidia
    ok "✅ 系统库安装完成"
}

activate_venv() {
    [[ -f "$PROJECT_ROOT/.venv/bin/activate" ]] || die "❌ 未找到虚拟环境: $PROJECT_ROOT/.venv/bin/activate"
    export PS1="${PS1-}"
    set +u
    source "$PROJECT_ROOT/.venv/bin/activate"
    set -u
}

clone_isaaclab_if_missing() {
    mkdir -p "$PROJECT_ROOT/third_party"
    if [[ ! -d "$PROJECT_ROOT/third_party/IsaacLab" ]]; then
        log "📥 克隆 IsaacLab..."
        git clone https://github.com/lehome-official/IsaacLab.git "$PROJECT_ROOT/third_party/IsaacLab"
    fi
    ok "✅ IsaacLab 目录已就绪"
}

check_imports() {
    python - "$@" <<'PY'
import importlib
import sys

failed = {}
for name in sys.argv[1:]:
    try:
        importlib.import_module(name)
    except Exception as exc:
        failed[name] = f"{type(exc).__name__}: {exc}"

if failed:
    for key, value in failed.items():
        print(f"{key}: {value}")
    raise SystemExit(1)

print("All imports passed:", ", ".join(sys.argv[1:]))
PY
}

backup_file() {
    local path="$1"
    [[ -e "$path" ]] || return 0
    cp "$path" "$path.bak.$(date +%Y%m%d_%H%M%S)"
}

safe_symlink() {
    local target="$1"
    local link_path="$2"

    mkdir -p "$(dirname -- "$link_path")"

    if [[ -L "$link_path" ]]; then
        local current
        current="$(readlink -f "$link_path" || true)"
        if [[ "$current" == "$(readlink -f "$target")" ]]; then
            ok "✅ 软链接已存在: $link_path -> $target"
            return 0
        fi
        rm -f "$link_path"
    elif [[ -e "$link_path" ]]; then
        mv "$link_path" "$link_path.bak.$(date +%Y%m%d_%H%M%S)"
    fi

    ln -s "$target" "$link_path"
    ok "✅ 已建立软链接: $link_path -> $target"
}
