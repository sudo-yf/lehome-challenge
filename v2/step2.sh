#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

usage() {
    cat <<'USAGE'
Usage: bash v2/20-finalize.sh

执行 IsaacSim EULA 授权、建立 _isaac_sim 软链接，并写入轻量 shell 快捷命令。
USAGE
}

if [[ "${1-}" == "-h" || "${1-}" == "--help" ]]; then
    usage
    exit 0
fi

ensure_repo_root
ensure_path
link_uv_cache
activate_venv

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
    bash "{project_root}/v2/save.sh" "$@"
}}
# --- End LeHome v2 ---'''
body = "\n".join(out).rstrip()
path.write_text((body + "\n\n" if body else "") + block + "\n")
PY

ok "✅ 已写入 ~/.bashrc 快捷命令：go / lehome-save"
ok "✅ 收尾完成；请手动执行一次: source ~/.bashrc"
