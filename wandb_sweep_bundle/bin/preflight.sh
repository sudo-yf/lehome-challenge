#!/usr/bin/env bash
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../lib" && pwd)/common.sh"
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../lib" && pwd)/wandb_env.sh"
ensure_workspace_root
prepare_wandb_env
ensure_path
activate_venv
MODEL="${MODEL:-xvla}"
SWEEP_CONFIG="${SWEEP_CONFIG_PATH:-configs/sweeps/xvla_stage2.yaml}"
TRAIN_CONFIG="${TRAIN_CONFIG_PATH:-}"
script="$BUNDLE_ROOT/scripts/wandb_sweep.py"
config_path="$(resolve_bundle_path "$SWEEP_CONFIG")"
cmd=(python "$script" --model "$MODEL" --config-file "$config_path" --print-project)
if [[ -n "$TRAIN_CONFIG" ]]; then
  cmd+=(--train-config "$(resolve_bundle_path "$TRAIN_CONFIG")")
fi
PROJECT="$(${cmd[@]})"
section "执行 W&B 预检"
kv "Workspace" "$LEHOME_WORKSPACE_ROOT"
kv "Bundle" "$BUNDLE_ROOT"
kv "Project" "$PROJECT"
preflight_cmd=(python "$BUNDLE_ROOT/scripts/wandb_preflight.py" --project "$PROJECT" --api-key-env WANDB_API_KEY --model "$MODEL" --name "${MODEL}-preflight")
cmd_preview "${preflight_cmd[*]}"
exec "${preflight_cmd[@]}"
