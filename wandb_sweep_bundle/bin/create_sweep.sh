#!/usr/bin/env bash
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../lib" && pwd)/common.sh"
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../lib" && pwd)/wandb_env.sh"
ensure_workspace_root
prepare_wandb_env
ensure_path
activate_venv
MODEL="${MODEL:-xvla}"
STEPS="${STEPS:-3000}"
COUNT="${COUNT:-8}"
SWEEP_CONFIG="${SWEEP_CONFIG_PATH:-configs/sweeps/xvla_stage2.yaml}"
TRAIN_CONFIG="${TRAIN_CONFIG_PATH:-}"
cmd=(python "$BUNDLE_ROOT/scripts/wandb_sweep.py" --model "$MODEL" --config-file "$(resolve_bundle_path "$SWEEP_CONFIG")" --steps "$STEPS" --count "$COUNT" --create-only)
if [[ -n "$TRAIN_CONFIG" ]]; then
  cmd+=(--train-config "$(resolve_bundle_path "$TRAIN_CONFIG")")
fi
cmd+=("$@")
section "创建 sweep"
cmd_preview "${cmd[*]}"
exec "${cmd[@]}"
