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
if [[ $# -gt 0 ]]; then
    shift
fi

case "$MODEL" in
    act)
        CONFIG="configs/train_act.yaml"
        ;;
    diffusion|dp)
        MODEL="diffusion"
        CONFIG="configs/train_dp.yaml"
        ;;
    smolvla)
        CONFIG="configs/train_smolvla.yaml"
        ;;
    *)
        echo "❌ 不支持的模型: $MODEL"
        echo "可选: act / diffusion / smolvla（兼容别名: dp）"
        exit 1
        ;;
esac

if [[ ! -f "$CONFIG" ]]; then
    echo "❌ 配置文件不存在: $CONFIG"
    exit 1
fi

# 兼容: just train act 1000
# 支持多种 steps 覆盖写法：
# - just train act 1000
# - just train act step1000
# - just train act steps=1000
# - just train act --steps 1000
# - just train act --steps=1000
STEPS_OVERRIDE=""
REMAIN_ARGS=()
while [[ $# -gt 0 ]]; do
    arg="$1"
    case "$arg" in
        --step|--steps|--max_steps|step|steps|max_steps)
            if [[ $# -lt 2 || ! "${2:-}" =~ ^[0-9]+$ ]]; then
                echo "❌ $arg 需要一个正整数值"
                exit 1
            fi
            STEPS_OVERRIDE="$2"
            shift 2
            continue
            ;;
        --step=*|--steps=*|--max_steps=*)
            val="${arg#*=}"
            if [[ ! "$val" =~ ^[0-9]+$ ]]; then
                echo "❌ 无效 steps 值: $val"
                exit 1
            fi
            STEPS_OVERRIDE="$val"
            shift
            continue
            ;;
        step=*|steps=*|step:*|steps:*|max_steps=*|max_steps:*)
            val="${arg#*=}"
            if [[ "$val" == "$arg" ]]; then
                val="${arg#*:}"
            fi
            if [[ ! "$val" =~ ^[0-9]+$ ]]; then
                echo "❌ 无效 steps 值: $val"
                exit 1
            fi
            STEPS_OVERRIDE="$val"
            shift
            continue
            ;;
        step[0-9]*|steps[0-9]*|max_steps[0-9]*)
            val="${arg##*[!0-9]}"
            if [[ ! "$val" =~ ^[0-9]+$ ]]; then
                echo "❌ 无效 steps 值: $arg"
                exit 1
            fi
            STEPS_OVERRIDE="$val"
            shift
            continue
            ;;
        *)
            # 兼容旧用法：第一个额外参数是纯数字时，视为 steps。
            if [[ -z "$STEPS_OVERRIDE" && ${#REMAIN_ARGS[@]} -eq 0 && "$arg" =~ ^[0-9]+$ ]]; then
                STEPS_OVERRIDE="$arg"
                shift
                continue
            fi
            REMAIN_ARGS+=("$arg")
            shift
            continue
            ;;
    esac
done

BS="$(awk '/^batch_size:/ {print $2; exit}' "$CONFIG" | tr -d '\r')"
STEPS="$(awk '/^steps:/ {print $2; exit}' "$CONFIG" | tr -d '\r')"
CFG_OUTPUT_DIR="$(awk '/^output_dir:/ {print $2; exit}' "$CONFIG" | tr -d '\r')"
BS="${BS:-unknown}"
STEPS="${STEPS:-unknown}"
CFG_OUTPUT_DIR="${CFG_OUTPUT_DIR:-outputs/train}"
TIMESTAMP="$(date +'%m-%d-%H:%M')"

RUN_CONFIG="$CONFIG"
TMP_CONFIG=""
if [[ -n "$STEPS_OVERRIDE" ]]; then
    TMP_CONFIG="$(mktemp /tmp/train_${MODEL}_steps_${STEPS_OVERRIDE}_XXXX.yaml)"
    cp "$CONFIG" "$TMP_CONFIG"
    if grep -q '^steps:' "$TMP_CONFIG"; then
        sed -i "s/^steps:.*/steps: ${STEPS_OVERRIDE}/" "$TMP_CONFIG"
    else
        printf '\nsteps: %s\n' "$STEPS_OVERRIDE" >> "$TMP_CONFIG"
    fi
    RUN_CONFIG="$TMP_CONFIG"
    STEPS="$STEPS_OVERRIDE"
fi
cleanup() {
    if [[ -n "$TMP_CONFIG" && -f "$TMP_CONFIG" ]]; then
        rm -f "$TMP_CONFIG"
    fi
}
trap cleanup EXIT

LOG_NAME="${TIMESTAMP}_${MODEL}_train_bs${BS}_s${STEPS}.log"

# lerobot 默认不覆盖已有输出目录（resume=false），提前给出明确提示。
HAS_OUTPUT_OVERRIDE=0
HAS_RESUME=0
for arg in "${REMAIN_ARGS[@]}"; do
    case "$arg" in
        --output_dir|--output_dir=*|--output-dir|--output-dir=*)
            HAS_OUTPUT_OVERRIDE=1
            ;;
        --resume|--resume=*|--resume=true|--resume=True|--resume=1)
            HAS_RESUME=1
            ;;
    esac
done
if [[ -d "$CFG_OUTPUT_DIR" && $HAS_OUTPUT_OVERRIDE -eq 0 && $HAS_RESUME -eq 0 ]]; then
    echo "❌ 输出目录已存在: $CFG_OUTPUT_DIR"
    echo "可选处理："
    echo "1) 改新目录再跑: just train $MODEL --output_dir outputs/train/${MODEL}_$(date +%m%d_%H%M%S)"
    echo "2) 继续训练: just train $MODEL --resume=true --config_path ${CFG_OUTPUT_DIR}/train_config.json"
    exit 2
fi

echo "🚀 开始训练: $MODEL"
echo "⚙️ 配置文件: $RUN_CONFIG"
echo "📦 输出目录(来自配置): $CFG_OUTPUT_DIR"
echo "📝 日志文件: logs/$LOG_NAME"
if [[ -n "$STEPS_OVERRIDE" ]]; then
    echo "⏱️ steps 覆盖: $STEPS_OVERRIDE"
fi

set +e
stdbuf -oL lerobot-train \
    --config_path="$RUN_CONFIG" \
    "${REMAIN_ARGS[@]}" \
    2>&1 | tee "$LOG_DIR/$LOG_NAME"
TRAIN_EXIT=${PIPESTATUS[0]}
set -e

if [[ $TRAIN_EXIT -ne 0 ]]; then
    echo "❌ 训练失败，退出码: $TRAIN_EXIT"
    exit "$TRAIN_EXIT"
fi

echo "✅ 训练完成: logs/$LOG_NAME"
echo "如需备份，可执行: just save <版本号>"
