#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
source "$SCRIPT_DIR/wandb.sh"

usage() {
    cat <<'USAGE'
Usage: bash lehome/sweep.sh [--preflight] [sweep-args...] [-- train-args...]

Repo-specific WandB sweep entry.

Environment defaults:
  MODEL=xvla
  SWEEP_METHOD=bayes
  SWEEP_COUNT=20
  SWEEP_MIN_ITER=3
  WANDB_ENABLE=true
  WANDB_MODE=online

Supported env helpers:
  WANDB_PROJECT / WANDB_ENTITY / WANDB_NOTES / WANDB_API_KEY / WANDB_BASE_URL
  WANDB_DISABLE_ARTIFACT=true|false
  MODEL / JOB_NAME / SWEEP_NAME / SWEEP_STEPS / SWEEP_METHOD / SWEEP_COUNT / SWEEP_MIN_ITER
  SWEEP_METRIC_NAME / SWEEP_METRIC_GOAL / SWEEP_CONFIG_PATH
  CREATE_ONLY=true|false / DRY_RUN=true|false / PRECHECK=true|false

Examples:
  PRECHECK=true WANDB_ENV_FILE=/root/data/wandb.md bash lehome/sweep.sh --model xvla
  WANDB_API_KEY=*** bash lehome/sweep.sh --model xvla --count 8 --steps 1000
  WANDB_API_KEY=*** CREATE_ONLY=true bash lehome/sweep.sh --model xvla --steps 3000
  DRY_RUN=true bash lehome/sweep.sh --model xvla --steps 1000 -- --job_name=xvla_sweep_top_long
USAGE
}

cli_dry_run=false
cli_precheck=false
forward_args=()
extra_train_args=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            usage
            exit 0
            ;;
        --dry-run)
            cli_dry_run=true
            forward_args+=("$1")
            shift
            ;;
        --preflight|--check)
            cli_precheck=true
            shift
            ;;
        --)
            shift
            while [[ $# -gt 0 ]]; do
                extra_train_args+=("$1")
                shift
            done
            ;;
        *)
            forward_args+=("$1")
            shift
            ;;
    esac
done

WANDB_PROJECT_WAS_SET="${WANDB_PROJECT+x}"
WANDB_ENTITY_WAS_SET="${WANDB_ENTITY+x}"
WANDB_NOTES_WAS_SET="${WANDB_NOTES+x}"
WANDB_BASE_URL_WAS_SET="${WANDB_BASE_URL+x}"

WANDB_ENABLE="${WANDB_ENABLE:-true}"
WANDB_MODE="${WANDB_MODE:-online}"
DRY_RUN_RAW="${DRY_RUN:-$cli_dry_run}"
CREATE_ONLY_RAW="${CREATE_ONLY:-false}"
PRECHECK_RAW="${PRECHECK:-${PREFLIGHT:-$cli_precheck}}"
WANDB_DISABLE_ARTIFACT="${WANDB_DISABLE_ARTIFACT:-false}"

DRY_RUN_BOOL="$(normalize_bool "$DRY_RUN_RAW" "DRY_RUN")"
CREATE_ONLY_BOOL="$(normalize_bool "$CREATE_ONLY_RAW" "CREATE_ONLY")"
PRECHECK_BOOL="$(normalize_bool "$PRECHECK_RAW" "PRECHECK")"
WANDB_DISABLE_ARTIFACT="$(normalize_bool "$WANDB_DISABLE_ARTIFACT" "WANDB_DISABLE_ARTIFACT")"

wandb_load_env

if [[ "$WANDB_ENABLE" != "true" ]]; then
    die "❌ sweep 入口要求 WANDB_ENABLE=true。"
fi

if [[ "$PRECHECK_BOOL" == "true" ]]; then
    [[ "$DRY_RUN_BOOL" == "false" ]] || die "❌ PRECHECK=true / --preflight 与 DRY_RUN=true 互斥。"
    [[ "$CREATE_ONLY_BOOL" == "false" ]] || die "❌ PRECHECK=true / --preflight 与 CREATE_ONLY=true 互斥。"
fi

if [[ "$DRY_RUN_BOOL" != "true" ]]; then
    [[ "$WANDB_MODE" == "online" ]] || die "❌ sweep 需要 WANDB_MODE=online；dry-run 之外不支持 offline/disabled。"
    [[ -n "${WANDB_API_KEY:-}" ]] || die "❌ sweep 需要设置 WANDB_API_KEY。"
fi

section "准备 WandB Sweep"
kv "Model" "${MODEL:-xvla}"
kv "Method" "${SWEEP_METHOD:-bayes}"
kv "Count" "${SWEEP_COUNT:-20}"
kv "Dry run" "$DRY_RUN_BOOL"
kv "Create only" "$CREATE_ONLY_BOOL"
kv "Precheck" "$PRECHECK_BOOL"

ensure_repo_root
ensure_path
activate_venv
wandb_assert_python_package >/dev/null

resolve_cmd=(python scripts/wandb_sweep.py)
resolve_cmd+=(--model "${MODEL:-xvla}")
resolve_cmd+=(--api-key-env "WANDB_API_KEY")
resolve_cmd+=(--wandb-mode "online")
resolve_cmd+=(--method "${SWEEP_METHOD:-bayes}")
resolve_cmd+=(--count "${SWEEP_COUNT:-20}")
resolve_cmd+=(--min-iter "${SWEEP_MIN_ITER:-3}")

cmd=(python scripts/wandb_sweep.py)
cmd+=(--model "${MODEL:-xvla}")
cmd+=(--api-key-env "WANDB_API_KEY")
cmd+=(--wandb-mode "online")
cmd+=(--method "${SWEEP_METHOD:-bayes}")
cmd+=(--count "${SWEEP_COUNT:-20}")
cmd+=(--min-iter "${SWEEP_MIN_ITER:-3}")

if [[ "$WANDB_PROJECT_WAS_SET" == "x" && -n "${WANDB_PROJECT:-}" ]]; then
    resolve_cmd+=(--project "$WANDB_PROJECT")
    cmd+=(--project "$WANDB_PROJECT")
fi
if [[ "$WANDB_ENTITY_WAS_SET" == "x" && -n "${WANDB_ENTITY:-}" ]]; then
    resolve_cmd+=(--entity "$WANDB_ENTITY")
    cmd+=(--entity "$WANDB_ENTITY")
fi
if [[ "$WANDB_BASE_URL_WAS_SET" == "x" && -n "${WANDB_BASE_URL:-}" ]]; then
    resolve_cmd+=(--base-url "$WANDB_BASE_URL")
    cmd+=(--base-url "$WANDB_BASE_URL")
fi
if [[ "$WANDB_NOTES_WAS_SET" == "x" && -n "${WANDB_NOTES:-}" ]]; then
    resolve_cmd+=(--notes "$WANDB_NOTES")
    cmd+=(--notes "$WANDB_NOTES")
fi
if [[ -n "${JOB_NAME:-}" ]]; then
    resolve_cmd+=(--job-name "$JOB_NAME")
    cmd+=(--job-name "$JOB_NAME")
fi
if [[ -n "${SWEEP_NAME:-}" ]]; then
    resolve_cmd+=(--name "$SWEEP_NAME")
    cmd+=(--name "$SWEEP_NAME")
fi
if [[ -n "${SWEEP_STEPS:-}" ]]; then
    resolve_cmd+=(--steps "$SWEEP_STEPS")
    cmd+=(--steps "$SWEEP_STEPS")
fi
if [[ -n "${SWEEP_METRIC_NAME:-}" ]]; then
    resolve_cmd+=(--metric-name "$SWEEP_METRIC_NAME")
    cmd+=(--metric-name "$SWEEP_METRIC_NAME")
fi
if [[ -n "${SWEEP_METRIC_GOAL:-}" ]]; then
    resolve_cmd+=(--metric-goal "$SWEEP_METRIC_GOAL")
    cmd+=(--metric-goal "$SWEEP_METRIC_GOAL")
fi
if [[ -n "${SWEEP_CONFIG_PATH:-}" ]]; then
    resolve_cmd+=(--config-file "$SWEEP_CONFIG_PATH")
    cmd+=(--config-file "$SWEEP_CONFIG_PATH")
fi
if [[ "$WANDB_DISABLE_ARTIFACT" == "true" ]]; then
    cmd+=(--disable-artifact)
fi
if [[ "$CREATE_ONLY_BOOL" == "true" ]]; then
    cmd+=(--create-only)
fi
if [[ "$DRY_RUN_BOOL" == "true" ]]; then
    cmd+=(--dry-run)
fi
for train_arg in "${extra_train_args[@]}"; do
    cmd+=("--train-arg=$train_arg")
done
for arg in "${forward_args[@]}"; do
    case "$arg" in
        --wandb-mode=*|--wandb-mode|--api-key-env|--api-key-env=*)
            die "❌ 请不要直接覆盖 shell 管理的 --wandb-mode / --api-key-env；请改用环境变量或默认在线模式。"
            ;;
        *)
            resolve_cmd+=("$arg")
            cmd+=("$arg")
            ;;
    esac
done

RESOLVED_PROJECT="$("${resolve_cmd[@]}" --print-project)"
WANDB_PROJECT="$RESOLVED_PROJECT"
kv "Project" "$RESOLVED_PROJECT"

if [[ "$PRECHECK_BOOL" == "true" ]]; then
    preflight_cmd=(python scripts/wandb_preflight.py)
    preflight_cmd+=(--project "$RESOLVED_PROJECT")
    preflight_cmd+=(--api-key-env "WANDB_API_KEY")
    preflight_cmd+=(--model "${MODEL:-xvla}")
    preflight_cmd+=(--name "${JOB_NAME:-${MODEL:-xvla}}-preflight")
    if [[ "$WANDB_ENTITY_WAS_SET" == "x" && -n "${WANDB_ENTITY:-}" ]]; then
        preflight_cmd+=(--entity "$WANDB_ENTITY")
    fi
    if [[ "$WANDB_BASE_URL_WAS_SET" == "x" && -n "${WANDB_BASE_URL:-}" ]]; then
        preflight_cmd+=(--base-url "$WANDB_BASE_URL")
    fi
    if [[ "$WANDB_NOTES_WAS_SET" == "x" && -n "${WANDB_NOTES:-}" ]]; then
        preflight_cmd+=(--notes "$WANDB_NOTES")
    fi

    section "执行 Sweep 预检"
    wandb_print_summary "${JOB_NAME:-${MODEL:-xvla}}-preflight"
    cmd_preview "${preflight_cmd[*]}"
    exec "${preflight_cmd[@]}"
fi

section "执行 Sweep"
wandb_print_summary "${JOB_NAME:-${MODEL:-xvla}}-sweep"
cmd_preview "${cmd[*]}"
exec "${cmd[@]}"
