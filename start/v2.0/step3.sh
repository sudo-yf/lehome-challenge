#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

usage() {
    cat <<'USAGE'
Usage: bash v2/30-data.sh [--with-full-dataset]

- --with-full-dataset  额外下载完整 dataset_challenge（含 depth 信息）
USAGE
}

WITH_FULL_DATASET=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --with-full-dataset)
            WITH_FULL_DATASET=1
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
activate_venv
command -v hf >/dev/null 2>&1 || die "❌ 未找到 hf 命令，请先执行 v2/10-install.sh"

log "📥 下载 Assets..."
hf download lehome/asset_challenge --repo-type dataset --local-dir Assets

log "📥 下载合并版示例数据集..."
hf download lehome/dataset_challenge_merged --repo-type dataset --local-dir Datasets/example

if [[ $WITH_FULL_DATASET -eq 1 ]]; then
    log "📥 下载完整 dataset_challenge..."
    hf download lehome/dataset_challenge --repo-type dataset --local-dir Datasets/example
else
    warn "⚠️ 未下载完整 dataset_challenge；如需 depth 信息，请附加 --with-full-dataset"
fi

ok "✅ 数据下载完成"
