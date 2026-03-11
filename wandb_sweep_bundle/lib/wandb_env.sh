#!/usr/bin/env bash
set -euo pipefail

WAND_ENV_LIB_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$WAND_ENV_LIB_DIR/common.sh"

normalize_bool() {
    local raw_value="${1:-}"
    local field_name="${2:-value}"
    local normalized="${raw_value,,}"
    case "$normalized" in
        true|1|yes|y|on) printf 'true
' ;;
        false|0|no|n|off|"") printf 'false
' ;;
        *) die "❌ 非法布尔值: ${field_name}=${raw_value}（可选: true / false）" ;;
    esac
}

load_wandb_env_file() {
    local env_file="${WANDB_ENV_FILE:-}"
    if [[ -z "$env_file" ]]; then
        if [[ -f "$LEHOME_WORKSPACE_ROOT/wandb.env" ]]; then
            env_file="$LEHOME_WORKSPACE_ROOT/wandb.env"
        elif [[ -f "/root/data/wandb.md" ]]; then
            env_file="/root/data/wandb.md"
        fi
    fi
    [[ -n "$env_file" && -f "$env_file" ]] || return 0

    while IFS= read -r raw_line || [[ -n "$raw_line" ]]; do
        local line="${raw_line#${raw_line%%[![:space:]]*}}"
        line="${line%${line##*[![:space:]]}}"
        [[ -n "$line" ]] || continue
        [[ "$line" == \#* ]] && continue
        if [[ "$line" == wandb_* ]]; then
            export WANDB_API_KEY="$line"
            continue
        fi
        if [[ "$line" == *=* ]]; then
            local key="${line%%=*}"
            local value="${line#*=}"
            key="${key%${key##*[![:space:]]}}"
            value="${value#${value%%[![:space:]]*}}"
            value="${value%${value##*[![:space:]]}}"
            if [[ ( "$value" == "'*'" ) || ( "$value" == '"*"' ) ]]; then
                value="${value:1:${#value}-2}"
            fi
            export "$key=$value"
        fi
    done < "$env_file"
}

prepare_wandb_env() {
    ensure_workspace_root
    load_wandb_env_file

    WANDB_ENABLE="$(normalize_bool "${WANDB_ENABLE:-true}" "WANDB_ENABLE")"
    WANDB_DISABLE_ARTIFACT="$(normalize_bool "${WANDB_DISABLE_ARTIFACT:-false}" "WANDB_DISABLE_ARTIFACT")"
    WANDB_MODE="${WANDB_MODE:-online}"
    WANDB_MODE="${WANDB_MODE,,}"
    case "$WANDB_MODE" in
        online|offline|disabled) ;;
        *) die "❌ 非法的 WANDB_MODE: $WANDB_MODE（可选: online / offline / disabled）" ;;
    esac

    local cache_base="${WANDB_CACHE_BASE:-}"
    if [[ -z "$cache_base" ]]; then
        if [[ -d "/root/data" ]]; then
            cache_base="/root/data/.cache"
        else
            cache_base="$LEHOME_WORKSPACE_ROOT/.cache"
        fi
    fi

    WANDB_DATA_DIR="${WANDB_DATA_DIR:-$cache_base/wandb-data}"
    WANDB_ARTIFACT_DIR="${WANDB_ARTIFACT_DIR:-$cache_base/wandb-artifacts}"
    TMPDIR="${TMPDIR:-$cache_base/tmp}"
    mkdir -p "$WANDB_DATA_DIR" "$WANDB_ARTIFACT_DIR" "$TMPDIR"

    export WANDB_ENABLE
    export WANDB_DISABLE_ARTIFACT
    export WANDB_MODE
    export WANDB_DATA_DIR
    export WANDB_ARTIFACT_DIR
    export TMPDIR
}
