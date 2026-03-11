#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

LOG_DIR="$PROJECT_ROOT/logs"
mkdir -p "$LOG_DIR"
ensure_repo_root

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

if [[ -z "${PYTORCH_CUDA_ALLOC_CONF:-}" ]]; then
    export PYTORCH_CUDA_ALLOC_CONF="expandable_segments:True"
fi

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
    xvla)
        CONFIG="configs/train_xvla.yaml"
        ;;
    *)
        echo "❌ 不支持的模型: $MODEL"
        echo "可选: act / diffusion（兼容别名: dp） / smolvla / xvla"
        exit 1
        ;;
esac

if [[ ! -f "$CONFIG" ]]; then
    echo "❌ 配置文件不存在: $CONFIG"
    exit 1
fi

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
ensure_tmp_config() {
    if [[ -z "$TMP_CONFIG" ]]; then
        TMP_CONFIG="$(mktemp /tmp/train_${MODEL}_config_XXXX.yaml)"
        cp "$CONFIG" "$TMP_CONFIG"
        RUN_CONFIG="$TMP_CONFIG"
    fi
}
if [[ -n "$STEPS_OVERRIDE" ]]; then
    ensure_tmp_config
    if grep -q '^steps:' "$TMP_CONFIG"; then
        sed -i "s/^steps:.*/steps: ${STEPS_OVERRIDE}/" "$TMP_CONFIG"
    else
        printf '\nsteps: %s\n' "$STEPS_OVERRIDE" >> "$TMP_CONFIG"
    fi
    STEPS="$STEPS_OVERRIDE"
fi
cleanup() {
    if [[ -n "$TMP_CONFIG" && -f "$TMP_CONFIG" ]]; then
        rm -f "$TMP_CONFIG"
    fi
}
trap cleanup EXIT

LOG_NAME="${TIMESTAMP}_${MODEL}_train_bs${BS}_s${STEPS}.log"

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

AUTO_OUTPUT_DIR=""
if [[ -d "$CFG_OUTPUT_DIR" && $HAS_OUTPUT_OVERRIDE -eq 0 && $HAS_RESUME -eq 0 ]]; then
    base_output_dir="$CFG_OUTPUT_DIR"
    suffix=2
    while [[ -d "${base_output_dir}_${suffix}" ]]; do
        ((suffix++))
    done
    AUTO_OUTPUT_DIR="${base_output_dir}_${suffix}"
    ensure_tmp_config
    if grep -q '^output_dir:' "$TMP_CONFIG"; then
        sed -i "s#^output_dir:.*#output_dir: ${AUTO_OUTPUT_DIR}#" "$TMP_CONFIG"
    else
        printf '\noutput_dir: %s\n' "$AUTO_OUTPUT_DIR" >> "$TMP_CONFIG"
    fi
    CFG_OUTPUT_DIR="$AUTO_OUTPUT_DIR"
fi

section "启动训练"
kv "Model" "$MODEL"
kv "Config" "$RUN_CONFIG"
kv "Output dir" "$CFG_OUTPUT_DIR"
kv "Log file" "logs/$LOG_NAME"
kv "CUDA alloc conf" "$PYTORCH_CUDA_ALLOC_CONF"
if [[ -n "$AUTO_OUTPUT_DIR" ]]; then
    warn "⚠️ 原目录已存在，自动顺延到: $AUTO_OUTPUT_DIR"
fi
if [[ -n "$STEPS_OVERRIDE" ]]; then
    kv "Steps override" "$STEPS_OVERRIDE"
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
echo "如需备份，可执行: just save 版本号 备注"
