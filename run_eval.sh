#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR"
LOG_DIR="$PROJECT_ROOT/logs"
mkdir -p "$LOG_DIR"
cd "$PROJECT_ROOT"

if [[ ! -f ".venv/bin/activate" ]]; then
    echo "❌ 未找到虚拟环境: $PROJECT_ROOT/.venv/bin/activate"
    echo "请先执行: just s1"
    exit 1
fi
source .venv/bin/activate

MODEL="${1:-act}"
if [[ "$MODEL" == "diffusion" ]]; then
    MODEL="dp"
fi
DEFAULT_POLICY_PATH="outputs/train/${MODEL}/checkpoints/last/pretrained_model"
POLICY_PATH="${2:-$DEFAULT_POLICY_PATH}"
GARMENT="${3:-top_long}"
EPISODES="${4:-10}"
DEFAULT_DATASET_ROOT="Datasets/example/${GARMENT}_merged"
DATASET_ROOT="${5:-$DEFAULT_DATASET_ROOT}"

TIMESTAMP="$(date +'%m-%d-%H:%M')"
LOG_NAME="${TIMESTAMP}_${MODEL}_eval_${GARMENT}_ep${EPISODES}.log"

echo "🧪 评估模型: $MODEL"
echo "📦 模型路径: $POLICY_PATH"
echo "📚 数据路径: $DATASET_ROOT"
echo "📝 日志文件: logs/$LOG_NAME"

if [[ ! -d "$DATASET_ROOT" ]]; then
    echo "⚠️ dataset_root 目录不存在: $DATASET_ROOT"
    echo "   若是自定义路径，请在第 5 个参数传入正确值。"
fi

EXTRA_ARGS=()
if [[ "$MODEL" == "smolvla" ]]; then
    EXTRA_ARGS+=(--task_description "fold the garment on the table")
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
