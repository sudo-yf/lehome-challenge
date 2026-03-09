#!/usr/bin/env bash
set -euo pipefail

WANDB_SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
if ! declare -F log >/dev/null 2>&1; then
    source "$WANDB_SCRIPT_DIR/common.sh"
fi

normalize_bool() {
    local raw_value="${1:-}"
    local field_name="${2:-value}"
    local normalized="${raw_value,,}"

    case "$normalized" in
        true|1|yes|y|on)
            printf 'true\n'
            ;;
        false|0|no|n|off|"")
            printf 'false\n'
            ;;
        *)
            die "❌ 非法布尔值: ${field_name}=${raw_value}（可选: true / false）"
            ;;
    esac
}

wandb_load_env_file() {
    local env_file="${WANDB_ENV_FILE:-/root/data/wandb.env}"
    [[ -f "$env_file" ]] || return 0

    while IFS= read -r raw_line || [[ -n "$raw_line" ]]; do
        local line="${raw_line#export }"
        line="${line#export\t}"
        line="${line#${line%%[![:space:]]*}}"
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

wandb_load_env() {
    wandb_load_env_file
    WANDB_ENABLE="$(normalize_bool "${WANDB_ENABLE:-false}" "WANDB_ENABLE")"
    WANDB_DISABLE_ARTIFACT="$(normalize_bool "${WANDB_DISABLE_ARTIFACT:-false}" "WANDB_DISABLE_ARTIFACT")"
    WANDB_MODE="${WANDB_MODE:-disabled}"
    WANDB_MODE="${WANDB_MODE,,}"

    case "$WANDB_MODE" in
        online|offline|disabled)
            ;;
        *)
            die "❌ 非法的 WANDB_MODE: $WANDB_MODE（可选: online / offline / disabled）"
            ;;
    esac

    WANDB_PROJECT="${WANDB_PROJECT:-lehome_xvla}"
    WANDB_ENTITY="${WANDB_ENTITY:-}"
    WANDB_NOTES="${WANDB_NOTES:-}"
    WANDB_RUN_ID="${WANDB_RUN_ID:-}"

    export WANDB_ENABLE
    export WANDB_DISABLE_ARTIFACT
    export WANDB_MODE
    export WANDB_PROJECT

    if [[ -n "$WANDB_ENTITY" ]]; then
        export WANDB_ENTITY
    else
        unset WANDB_ENTITY
    fi

    if [[ -n "$WANDB_NOTES" ]]; then
        export WANDB_NOTES
    else
        unset WANDB_NOTES
    fi

    if [[ -n "$WANDB_RUN_ID" ]]; then
        export WANDB_RUN_ID
    else
        unset WANDB_RUN_ID
    fi
}

wandb_effective_enable() {
    if [[ "$WANDB_ENABLE" != "true" || "$WANDB_MODE" == "disabled" ]]; then
        printf 'false\n'
        return 0
    fi

    printf 'true\n'
}

wandb_assert_python_package() {
    ensure_repo_root
    ensure_path
    [[ -f "$PROJECT_ROOT/.venv/bin/activate" ]] || die "❌ 未找到 $PROJECT_ROOT/.venv，无法检查 wandb 依赖。"
    activate_venv

    python - <<'PY'
import wandb  # noqa: F401
print("wandb import ok")
PY
}

wandb_print_summary() {
    local job_name="${1:-<unset>}"
    local effective_enable
    effective_enable="$(wandb_effective_enable)"

    log "🧭 WandB 配置: enable=${effective_enable} mode=${WANDB_MODE} project=${WANDB_PROJECT} job_name=${job_name} artifact_disabled=${WANDB_DISABLE_ARTIFACT}"
}

wandb_preflight_train() {
    wandb_load_env

    if [[ "$WANDB_ENABLE" == "false" ]]; then
        return 0
    fi

    case "$WANDB_MODE" in
        online)
            [[ -n "${WANDB_API_KEY:-}" ]] || die "❌ WANDB_MODE=online 时必须先设置 WANDB_API_KEY 环境变量。"
            wandb_assert_python_package >/dev/null
            ;;
        offline)
            wandb_assert_python_package >/dev/null
            ;;
        disabled)
            ;;
    esac
}

main() {
    wandb_preflight_train
    wandb_print_summary
    ok "✅ WandB 预检通过"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
