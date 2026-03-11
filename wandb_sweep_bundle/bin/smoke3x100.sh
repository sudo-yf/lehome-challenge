#!/usr/bin/env bash
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../lib" && pwd)/common.sh"
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../lib" && pwd)/wandb_env.sh"
ensure_workspace_root
prepare_wandb_env
ensure_path
activate_venv
MODEL="${MODEL:-xvla}"
SMOKE_MODE="${SMOKE_MODE:-offline}"
SWEEP_CONFIG="${SWEEP_CONFIG_PATH:-configs/sweeps/xvla_stage2.yaml}"
TRAIN_CONFIG="${TRAIN_CONFIG_PATH:-}"
export WANDB_DISABLE_ARTIFACT="${WANDB_DISABLE_ARTIFACT:-true}"
if [[ "$SMOKE_MODE" == "offline" ]]; then
  export HF_HUB_OFFLINE="${HF_HUB_OFFLINE:-1}"
  export TRANSFORMERS_OFFLINE="${TRANSFORMERS_OFFLINE:-1}"
fi
cmd=(python "$BUNDLE_ROOT/scripts/wandb_sweep.py" --model "$MODEL" --config-file "$(resolve_bundle_path "$SWEEP_CONFIG")" --count 3 --steps 100 --disable-artifact)
if [[ -n "$TRAIN_CONFIG" ]]; then
  cmd+=(--train-config "$(resolve_bundle_path "$TRAIN_CONFIG")")
fi
cmd+=("$@")
section "执行 3 x 100 步 smoke"
kv "Mode" "$SMOKE_MODE"
cmd_preview "${cmd[*]}"
exec "${cmd[@]}"
