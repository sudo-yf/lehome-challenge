#!/bin/bash
# 训练进度监控脚本

echo "=========================================="
echo "训练进度监控"
echo "=========================================="
echo ""

# 检查训练进程
echo "1. 训练进程状态:"
if ps aux | grep "lerobot-train" | grep -v grep > /dev/null; then
    echo "   ✅ 训练进程正在运行"
    ps aux | grep "lerobot-train" | grep -v grep | head -1 | awk '{print "   进程ID: " $2 ", CPU: " $3 "%, 内存: " $4 "%"}'
else
    echo "   ❌ 训练进程未运行"
fi
echo ""

# 显示最新训练步数
echo "2. 最新训练进度:"
if [ -f logs/03-11_18-34-43_lerobot_train_xvla.log ]; then
    LATEST_STEP=$(grep "step:" logs/03-11_18-34-43_lerobot_train_xvla.log | tail -1)
    if [ -n "$LATEST_STEP" ]; then
        echo "   $LATEST_STEP"
    else
        echo "   还未开始训练步数记录"
    fi
else
    echo "   日志文件不存在"
fi
echo ""

# 检查checkpoint
echo "3. 已保存的Checkpoint:"
if [ -d outputs/train/top_long/xvla_base_3w_steps_final/checkpoints ]; then
    ls -1 outputs/train/top_long/xvla_base_3w_steps_final/checkpoints/ | grep -E "^[0-9]" | sort -n
else
    echo "   还未生成checkpoint（将在5000步时首次保存）"
fi
echo ""

echo "=========================================="
echo "实时监控命令:"
echo "tail -f logs/03-11_18-34-43_lerobot_train_xvla.log | grep 'step:'"
echo "=========================================="
