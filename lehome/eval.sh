#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

SCRIPT_PATH="$SCRIPT_DIR/$(basename -- "${BASH_SOURCE[0]}")"
LOG_DIR="$PROJECT_ROOT/logs"
mkdir -p "$LOG_DIR"
ensure_repo_root

if [[ "${LEHOME_EVAL_XVFB_WRAPPED:-0}" != "1" ]]; then
    if ! command -v xvfb-run >/dev/null 2>&1; then
        echo "❌ 未找到 xvfb-run，请先安装/启用 xvfb-run 后再评估。"
        exit 1
    fi
    echo "🖥️ 评估默认启用 xvfb-run -a；正在进入虚拟显示环境..."
    exec xvfb-run -a env LEHOME_EVAL_XVFB_WRAPPED=1 bash "$SCRIPT_PATH" "$@"
fi

CACHE_ROOT="$PROJECT_ROOT/.cache"
HF_CACHE_ROOT="$CACHE_ROOT/huggingface"
TORCH_CACHE_ROOT="$CACHE_ROOT/torch"
mkdir -p "$HF_CACHE_ROOT/datasets" "$HF_CACHE_ROOT/hub" "$HF_CACHE_ROOT/transformers" "$TORCH_CACHE_ROOT/hub/checkpoints"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$CACHE_ROOT}"
export HF_HOME="${HF_HOME:-$HF_CACHE_ROOT}"
export HF_DATASETS_CACHE="${HF_DATASETS_CACHE:-$HF_CACHE_ROOT/datasets}"
export HF_HUB_CACHE="${HF_HUB_CACHE:-$HF_CACHE_ROOT/hub}"
export HUGGINGFACE_HUB_CACHE="${HUGGINGFACE_HUB_CACHE:-$HF_HUB_CACHE}"
export TRANSFORMERS_CACHE="${TRANSFORMERS_CACHE:-$HF_CACHE_ROOT/transformers}"
export TORCH_HOME="${TORCH_HOME:-$TORCH_CACHE_ROOT}"

activate_venv

MODEL="${1:-act}"
if [[ $# -gt 0 ]]; then
    shift
fi

case "$MODEL" in
    act)
        DEFAULT_RUN_DIR="outputs/train/act_top_long"
        ;;
    diffusion|dp)
        MODEL="diffusion"
        DEFAULT_RUN_DIR="outputs/train/dp_top_long"
        ;;
    smolvla)
        DEFAULT_RUN_DIR="outputs/train/smolvla_top_long"
        ;;
    xvla)
        DEFAULT_RUN_DIR="outputs/train/top_long/xvla_base_3w_steps"
        ;;
    *)
        echo "❌ 不支持的模型: $MODEL"
        echo "可选: act / diffusion（兼容别名: dp） / smolvla / xvla"
        exit 1
        ;;
esac

DEFAULT_POLICY_PATH="${DEFAULT_RUN_DIR}/checkpoints/last/pretrained_model"
POLICY_PATH="${1:-$DEFAULT_POLICY_PATH}"
if [[ $# -gt 0 ]]; then
    shift
fi
GARMENT="${1:-top_long}"
if [[ $# -gt 0 ]]; then
    shift
fi
EPISODES="${1:-5}"
if [[ $# -gt 0 ]]; then
    shift
fi
DEFAULT_DATASET_ROOT="Datasets/example/${GARMENT}_merged"
DATASET_ROOT="${1:-$DEFAULT_DATASET_ROOT}"
if [[ $# -gt 0 ]]; then
    shift
fi
EXTRA_ARGS=("$@")

TIMESTAMP="$(date +'%m-%d-%H:%M')"
LOG_NAME="${TIMESTAMP}_${MODEL}_eval_${GARMENT}_ep${EPISODES}.log"

section "启动评估"
kv "Model" "$MODEL"
kv "Policy path" "$POLICY_PATH"
kv "Dataset root" "$DATASET_ROOT"
kv "Log file" "logs/$LOG_NAME"
kv "XVFB" "enabled (DISPLAY=${DISPLAY:-unset})"

if [[ ! -d "$DATASET_ROOT" ]]; then
    echo "⚠️ dataset_root 目录不存在: $DATASET_ROOT"
    echo "   若是自定义路径，请在第 5 个参数传入正确值。"
fi

if [[ ! -d "$POLICY_PATH" ]]; then
    echo "⚠️ policy_path 目录不存在: $POLICY_PATH"
fi

HAS_TASK_DESCRIPTION=0
HAS_HEADLESS=0
for arg in "${EXTRA_ARGS[@]}"; do
    if [[ "$arg" == "--task_description" || "$arg" == --task_description=* ]]; then
        HAS_TASK_DESCRIPTION=1
    fi
    if [[ "$arg" == "--headless" ]]; then
        HAS_HEADLESS=1
    fi
done
if [[ "$MODEL" == "smolvla" && $HAS_TASK_DESCRIPTION -eq 0 ]]; then
    EXTRA_ARGS+=(--task_description "fold the garment on the table")
fi
if [[ $HAS_HEADLESS -eq 0 ]]; then
    EXTRA_ARGS+=(--headless)
    echo "🧱 默认附加参数: --headless"
else
    echo "🧱 检测到显式参数: --headless"
fi
if (( ${#EXTRA_ARGS[@]} > 0 )); then
    echo "🧾 额外参数: ${EXTRA_ARGS[*]}"
fi

set +e
python -m scripts.eval \
    --policy_type lerobot \
    --policy_path "$POLICY_PATH" \
    --dataset_root "$DATASET_ROOT" \
    --garment_type "$GARMENT" \
    --num_episodes "$EPISODES" \
    --enable_cameras \
    --device cpu \
    "${EXTRA_ARGS[@]}" \
    2>&1 | tee "$LOG_DIR/$LOG_NAME"
EVAL_EXIT=${PIPESTATUS[0]}
set -e

if [[ $EVAL_EXIT -ne 0 ]]; then
    echo "❌ 评估失败，退出码: $EVAL_EXIT"
    exit "$EVAL_EXIT"
fi

echo "✅ 评估完成: logs/$LOG_NAME"
