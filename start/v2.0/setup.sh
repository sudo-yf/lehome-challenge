#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

usage() {
    cat <<'USAGE'
Usage: bash v2/setup.sh [--install-system-libs] [--with-full-dataset]

推荐顺序：
1. 可选执行 vpn.sh
2. 执行 step1.sh
3. 执行 step2.sh
4. 执行 step3.sh
5. 后续使用 train.sh / eval.sh / save.sh
USAGE
}

STEP1_ARGS=()
STEP3_ARGS=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --install-system-libs)
            STEP1_ARGS+=("$1")
            ;;
        --with-full-dataset)
            STEP3_ARGS+=("$1")
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "❌ 不支持的参数: $1" >&2
            exit 1
            ;;
    esac
    shift
done

bash "$SCRIPT_DIR/step1.sh" "${STEP1_ARGS[@]}"
bash "$SCRIPT_DIR/step2.sh"
bash "$SCRIPT_DIR/step3.sh" "${STEP3_ARGS[@]}"
