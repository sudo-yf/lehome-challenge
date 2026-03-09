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
case "$MODEL" in
    act|dp|smolvla) ;;
    diffusion) MODEL="dp" ;;  # 兼容旧写法
    *)
        echo "❌ 不支持的模型: $MODEL"
        echo "可选: act / dp / smolvla"
        exit 1
        ;;
esac

CONFIG="configs/train_${MODEL}.yaml"
if [[ ! -f "$CONFIG" ]]; then
    echo "❌ 配置文件不存在: $CONFIG"
    exit 1
fi

BS="$(awk '/^batch_size:/ {print $2; exit}' "$CONFIG" | tr -d '\r')"
STEPS="$(awk '/^steps:/ {print $2; exit}' "$CONFIG" | tr -d '\r')"
BS="${BS:-unknown}"
STEPS="${STEPS:-unknown}"
TIMESTAMP="$(date +'%m-%d-%H:%M')"

LOG_NAME="${TIMESTAMP}_${MODEL}_train_bs${BS}_s${STEPS}.log"
OUTPUT_DIR="outputs/train/${MODEL}"
mkdir -p "$OUTPUT_DIR"

echo "🚀 开始训练: $MODEL"
echo "📝 日志文件: logs/$LOG_NAME"

set +e
stdbuf -oL lerobot-train \
    --config_path="$CONFIG" \
    --output_dir="$OUTPUT_DIR" \
    --wandb.enable=true \
    --wandb.name="${TIMESTAMP}_${MODEL}_train" \
    --device="cuda" \
    2>&1 | tee "$LOG_DIR/$LOG_NAME"
TRAIN_EXIT=${PIPESTATUS[0]}
set -e

if [[ $TRAIN_EXIT -ne 0 ]]; then
    echo "❌ 训练失败，退出码: $TRAIN_EXIT"
    exit "$TRAIN_EXIT"
fi

echo "✅ 训练完成: logs/$LOG_NAME"
echo "如需备份，可执行: just save <版本号>"
