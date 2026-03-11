#!/bin/bash
# 系统级定时检查脚本

LOG_FILE="/root/data/lehome-challenge/logs/cron_check_$(date +%Y%m%d).log"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

echo "[$TIMESTAMP] ==================== 开始检查 ====================" >> "$LOG_FILE"

cd /root/data/lehome-challenge

# 检查训练进程
TRAIN_PROCESS=$(ps aux | grep "lerobot-train" | grep -v grep | wc -l)
echo "[$TIMESTAMP] 训练进程数: $TRAIN_PROCESS" >> "$LOG_FILE"

# 检查最新的评估日志
LATEST_EVAL_LOG=$(ls -t logs/*eval*.log 2>/dev/null | head -1)
if [ -n "$LATEST_EVAL_LOG" ]; then
    SUCCESS_RATE=$(grep "Success Rate:" "$LATEST_EVAL_LOG" | tail -1 | grep -oE "[0-9]+\.[0-9]+")
    if [ -n "$SUCCESS_RATE" ]; then
        echo "[$TIMESTAMP] 最新成功率: $SUCCESS_RATE%" >> "$LOG_FILE"
        
        # 检查成功率是否<50%
        if (( $(echo "$SUCCESS_RATE < 50" | bc -l) )); then
            echo "[$TIMESTAMP] ⚠️ 警告：成功率 $SUCCESS_RATE% < 50%！" >> "$LOG_FILE"
            
            # 检查是否有训练或评估进程在运行
            EVAL_PROCESS=$(ps aux | grep "scripts.eval" | grep -v grep | wc -l)
            
            if [ $TRAIN_PROCESS -eq 0 ] && [ $EVAL_PROCESS -eq 0 ]; then
                echo "[$TIMESTAMP] ❌ 错误：没有训练或评估进程在运行！需要修复！" >> "$LOG_FILE"
                # 这里可以添加自动修复逻辑或发送通知
            else
                echo "[$TIMESTAMP] ✅ 有进程在运行中（训练:$TRAIN_PROCESS, 评估:$EVAL_PROCESS）" >> "$LOG_FILE"
            fi
        else
            echo "[$TIMESTAMP] ✅ 成功率达标（$SUCCESS_RATE% >= 50%）" >> "$LOG_FILE"
        fi
    fi
fi

# 检查自动化脚本状态
AUTO_SCRIPT=$(ps aux | grep "auto_train_eval.sh" | grep -v grep | wc -l)
echo "[$TIMESTAMP] 自动化脚本进程数: $AUTO_SCRIPT" >> "$LOG_FILE"

echo "[$TIMESTAMP] ==================== 检查完成 ====================" >> "$LOG_FILE"
