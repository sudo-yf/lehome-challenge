#!/usr/bin/env bash
set -euo pipefail

BUNDLE_LIB_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
BUNDLE_ROOT="$(cd -- "$BUNDLE_LIB_DIR/.." && pwd)"

BLUE='[0;34m'
GREEN='[0;32m'
YELLOW='[1;33m'
RED='[0;31m'
NC='[0m'

log() { echo -e "${BLUE}$*${NC}"; }
ok() { echo -e "${GREEN}$*${NC}"; }
warn() { echo -e "${YELLOW}$*${NC}"; }
die() { echo -e "${RED}$*${NC}" >&2; exit 1; }
rule() { printf '%b%s%b
' "$BLUE" "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" "$NC"; }
section() { echo; rule; log "▶ $*"; rule; }
cmd_preview() { log "💻 $*"; }
kv() { local key="$1"; shift; printf '%b%-18s%b %s
' "$BLUE" "${key}:" "$NC" "$*"; }

bundle_root() { printf '%s
' "$BUNDLE_ROOT"; }

_search_upward() {
    local current="$1"
    while true; do
        if [[ -f "$current/pyproject.toml" ]]; then
            printf '%s
' "$current"
            return 0
        fi
        [[ "$current" == "/" ]] && break
        current="$(dirname -- "$current")"
    done
    return 1
}

find_workspace_root() {
    if [[ -n "${LEHOME_WORKSPACE_ROOT:-}" ]]; then
        cd "$LEHOME_WORKSPACE_ROOT" >/dev/null 2>&1 || die "❌ LEHOME_WORKSPACE_ROOT 不存在: $LEHOME_WORKSPACE_ROOT"
        pwd
        return 0
    fi

    local found=''
    found="$(_search_upward "$PWD" || true)"
    if [[ -n "$found" ]]; then
        printf '%s
' "$found"
        return 0
    fi

    found="$(_search_upward "$BUNDLE_ROOT" || true)"
    if [[ -n "$found" ]]; then
        printf '%s
' "$found"
        return 0
    fi

    die "❌ 无法自动定位工作区根目录，请先设置 LEHOME_WORKSPACE_ROOT"
}

ensure_workspace_root() {
    export LEHOME_WORKSPACE_ROOT="$(find_workspace_root)"
    cd "$LEHOME_WORKSPACE_ROOT"
}

ensure_path() {
    export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"
}

activate_venv() {
    [[ -n "${LEHOME_WORKSPACE_ROOT:-}" ]] || die "❌ 请先调用 ensure_workspace_root"
    [[ -f "$LEHOME_WORKSPACE_ROOT/.venv/bin/activate" ]] || die "❌ 未找到虚拟环境: $LEHOME_WORKSPACE_ROOT/.venv/bin/activate"
    export PS1="${PS1-}"
    set +u
    source "$LEHOME_WORKSPACE_ROOT/.venv/bin/activate"
    set -u
}

resolve_bundle_path() {
    local raw="$1"
    if [[ "$raw" == /* ]]; then
        printf '%s
' "$raw"
    else
        printf '%s/%s
' "$BUNDLE_ROOT" "$raw"
    fi
}

append_optional_flag() {
    local -n arr_ref=$1
    local flag_name="$2"
    local flag_value="${3:-}"
    if [[ -n "$flag_value" ]]; then
        arr_ref+=("$flag_name" "$flag_value")
    fi
}
