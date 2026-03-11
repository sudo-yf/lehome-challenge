#!/bin/bash
# 监控自动化流程状态

echo "=========================================="
echo "自动化流程监控"
echo "=========================================="
echo ""

# 检查自动化脚本是否在运行
if ps aux | grep "auto_train_eval.sh" | grep -v grep > /dev/null; then
    echo "✅ 自动化流程正在运行"
else
    echo "❌ 自动化流程未运行"
fi
echo ""

# 显示最新日志
echo "最新日志内容："
echo "----------------------------------------"
if ls /root/data/lehome-challenge/logs/auto_workflow_*.log 1> /dev/null 2>&1; then
    tail -20 $(ls -t /root/data/lehome-challenge/logs/auto_workflow_*.log | head -1)
else
    echo "还未生成日志文件"
fi
echo ""

# 显示当前训练进度
echo "=========================================="
echo "当前训练进度："
echo "=========================================="
if [ -f logs/03-11_18-34-43_lerobot_train_xvla.log ]; then
    LATEST_STEP=$(grep "step:" logs/03-11_18-34-43_lerobot_train_xvla.log | tail -1)
    if [ -n "$LATEST_STEP" ]; then
        echo "$LATEST_STEP"
    else
        echo "还未开始训练"
    fi
else
    echo "训练日志不存在"
fi
echo ""

echo "=========================================="
echo "实时监控命令："
echo "tail -f logs/auto_workflow_*.log"
echo "=========================================="
