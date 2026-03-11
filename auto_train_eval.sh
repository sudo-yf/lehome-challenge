#!/bin/bash
# 自动化训练和评估流程
# 1. 等待XVLA训练完成
# 2. 评估XVLA模型
# 3. 如果成功率<50%，训练ACT模型
# 4. 评估ACT模型

set -e

LOG_FILE="/root/data/lehome-challenge/logs/auto_workflow_$(date +%m-%d_%H-%M-%S).log"
VENV_PYTHON="/root/data/lehome-challenge/.venv/bin/python"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log "=========================================="
log "自动化训练评估流程启动"
log "=========================================="

# 1. 等待XVLA训练完成（必须到30000步）
log "步骤1: 等待XVLA训练完成（目标：30000步）..."
while true; do
    # 检查是否有30000步的checkpoint
    if [ -f "outputs/train/top_long/xvla_base_3w_steps_final/checkpoints/030000/pretrained_model/model.safetensors" ]; then
        log "✅ XVLA训练已完成（30000步）！"
        break
    fi

    # 检查训练进程是否还在运行
    if ! pgrep -f "lerobot-train.*train_xvla.yaml" > /dev/null; then
        log "⚠️ 训练进程未运行，检查是否已完成..."
        if [ -f "outputs/train/top_long/xvla_base_3w_steps_final/checkpoints/030000/pretrained_model/model.safetensors" ]; then
            log "✅ 找到30000步的checkpoint，训练已完成"
            break
        else
            log "❌ 训练进程已停止但未找到30000步checkpoint，请检查"
            exit 1
        fi
    fi

    # 显示当前进度
    CURRENT_STEP=$(grep "step:" logs/03-11_18-34-43_lerobot_train_xvla.log 2>/dev/null | tail -1 | grep -oE "step:[0-9]+K" || echo "未知")
    log "训练进行中... 当前进度: $CURRENT_STEP / 30K，等待120秒后再检查..."
    sleep 120
done

# 2. 评估XVLA模型
log "=========================================="
log "步骤2: 评估XVLA模型..."
log "=========================================="

XVLA_EVAL_LOG="logs/$(date +%m-%d_%H-%M-%S)_eval_xvla_final.log"

$VENV_PYTHON -m scripts.eval \
    --policy_type lerobot \
    --policy_path outputs/train/top_long/xvla_base_3w_steps_final/checkpoints/last/pretrained_model \
    --garment_type "top_long" \
    --dataset_root Datasets/example/top_long_merged \
    --num_episodes 2 \
    --device cpu \
    --headless > "$XVLA_EVAL_LOG" 2>&1

# 提取成功率
XVLA_SUCCESS_RATE=$(grep "Success Rate:" "$XVLA_EVAL_LOG" | tail -1 | grep -oE "[0-9]+\.[0-9]+")

log "XVLA模型评估完成！"
log "成功率: ${XVLA_SUCCESS_RATE}%"

# 3. 判断是否需要训练ACT
if (( $(echo "$XVLA_SUCCESS_RATE < 50" | bc -l) )); then
    log "=========================================="
    log "成功率低于50%，开始训练ACT模型..."
    log "=========================================="

    # 训练ACT模型
    ACT_TRAIN_LOG="logs/$(date +%m-%d_%H-%M-%S)_train_act.log"

    log "启动ACT训练（30000步）..."
    $VENV_PYTHON -m lerobot.scripts.train \
        --config_path configs/train_act.yaml \
        --output_dir outputs/train/top_long/act_30k \
        --steps 30000 \
        --save_freq 5000 \
        --batch_size 16 > "$ACT_TRAIN_LOG" 2>&1

    log "✅ ACT训练完成！"

    # 4. 评估ACT模型
    log "=========================================="
    log "步骤4: 评估ACT模型..."
    log "=========================================="

    ACT_EVAL_LOG="logs/$(date +%m-%d_%H-%M-%S)_eval_act_final.log"

    $VENV_PYTHON -m scripts.eval \
        --policy_type lerobot \
        --policy_path outputs/train/top_long/act_30k/checkpoints/last/pretrained_model \
        --garment_type "top_long" \
        --dataset_root Datasets/example/top_long_merged \
        --num_episodes 2 \
        --device cpu \
        --headless > "$ACT_EVAL_LOG" 2>&1

    ACT_SUCCESS_RATE=$(grep "Success Rate:" "$ACT_EVAL_LOG" | tail -1 | grep -oE "[0-9]+\.[0-9]+")

    log "ACT模型评估完成！"
    log "成功率: ${ACT_SUCCESS_RATE}%"
    log "官方baseline: 57%"

    if (( $(echo "$ACT_SUCCESS_RATE >= 57" | bc -l) )); then
        log "✅ ACT成功率达到或超过官方baseline (57%)"
    else
        log "⚠️ ACT成功率未达到官方baseline (57%)"
    fi
else
    log "=========================================="
    log "✅ XVLA成功率 >= 50%，无需训练ACT"
    log "=========================================="
fi

log "=========================================="
log "自动化流程完成！"
log "=========================================="
log "最终结果："
log "- XVLA成功率: ${XVLA_SUCCESS_RATE}%"
if [ -n "$ACT_SUCCESS_RATE" ]; then
    log "- ACT成功率: ${ACT_SUCCESS_RATE}%"
fi
log "详细日志: $LOG_FILE"
