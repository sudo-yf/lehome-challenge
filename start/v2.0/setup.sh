#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

usage() {
    cat <<'USAGE'
Usage: bash start/v2.0/setup.sh [--install-system-libs] [--with-full-dataset]

推荐顺序：
1. 可选执行 vpn.sh
2. 执行 install.sh
3. 执行 finalize.sh
4. 执行 data.sh
5. 后续使用 train.sh / eval.sh / save.sh
USAGE
}

INSTALL_ARGS=()
DATA_ARGS=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --install-system-libs)
            INSTALL_ARGS+=("$1")
            ;;
        --with-full-dataset)
            DATA_ARGS+=("$1")
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

invoke_v2_script "install.sh" "${INSTALL_ARGS[@]}"
invoke_v2_script "finalize.sh"
invoke_v2_script "data.sh" "${DATA_ARGS[@]}"

ok "✅ v2 主流程执行完成"
