#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

usage() {
    cat <<'USAGE'
Usage: bash lehome/prepare.sh [--install-system-libs]

执行内容：
- 环境安装与 `uv sync`
- IsaacLab / LeHome / HuggingFace CLI 安装
- 核心导入校验
- IsaacSim EULA 授权
- `_isaac_sim` 软链接
- 轻量 shell 快捷命令写入

参数：
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

section "准备环境"
kv "Project root" "$PROJECT_ROOT"
kv "Install libs" "$INSTALL_SYSTEM_LIBS"

ensure_repo_root
ensure_uv
link_uv_cache

if [[ $INSTALL_SYSTEM_LIBS -eq 1 ]]; then
    install_system_libs
else
    warn "⚠️ 未安装系统图形库；若后续 IsaacSim/FFmpeg 报错，请重新执行并带上 --install-system-libs"
fi

section "同步 Python 依赖"
cmd_preview 'uv sync --locked'
uv sync --locked
ok "✅ uv sync --locked 完成"

section "安装 IsaacLab / LeHome"
clone_isaaclab_if_missing
activate_venv
cmd_preview './third_party/IsaacLab/isaaclab.sh -i none'
./third_party/IsaacLab/isaaclab.sh -i none
cmd_preview 'uv pip install -e ./source/lehome'
uv pip install -e ./source/lehome
cmd_preview 'uv pip install "huggingface_hub[cli]"'
uv pip install "huggingface_hub[cli]"

section "校验核心导入"
check_imports torch torchvision lerobot isaacsim lehome isaaclab isaaclab_tasks isaaclab_rl isaaclab_mimic isaaclab_assets isaaclab_contrib
ok "✅ 核心环境安装完成"

section "收尾配置"
warn "⚠️ 即将触发 IsaacSim EULA；若终端提示接受协议，请按提示输入 Yes。"
python -c "import isaacsim; print('IsaacSim import ok')"
ISAACSIM_PKG_PATH="$(python -c "import isaacsim, os; print(os.path.dirname(isaacsim.__file__))")"
[[ -n "$ISAACSIM_PKG_PATH" ]] || die "❌ 无法解析 isaacsim 安装路径"
safe_symlink "$ISAACSIM_PKG_PATH" "$PROJECT_ROOT/third_party/IsaacLab/_isaac_sim"

BASHRC="$HOME/.bashrc"
touch "$BASHRC"
backup_file "$BASHRC"
python - "$BASHRC" "$PROJECT_ROOT" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
project_root = sys.argv[2]
text = path.read_text() if path.exists() else ""
begin = "# --- LeHome v2 ---"
end = "# --- End LeHome v2 ---"
lines = text.splitlines()
out = []
skip = False
for line in lines:
    stripped = line.strip()
    if stripped == begin:
        skip = True
        continue
    if stripped == end:
        skip = False
        continue
    if not skip:
        out.append(line)
block = f'''{begin}
export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"
go() {{
    cd "{project_root}" && source .venv/bin/activate
}}
lehome-save() {{
    bash "{project_root}/lehome/allinone.sh save" "$@"
}}
# --- End LeHome v2 ---'''
body = "\n".join(out).rstrip()
path.write_text((body + "\n\n" if body else "") + block + "\n")
PY

ok "✅ 已写入 ~/.bashrc 快捷命令：go / lehome-save"
ok "✅ 环境准备完成；请手动执行一次: source ~/.bashrc"
