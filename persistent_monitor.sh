#!/bin/bash
# 持久化监控脚本 - 只要机器开机就会一直运行

LOG_FILE="/root/data/lehome-challenge/logs/persistent_monitor.log"

echo "[$(date '+%Y-%m-%d %H:%M:%S')] 持久化监控脚本启动" >> "$LOG_FILE"

while true; do
    TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
    
    cd /root/data/lehome-challenge
    
    # 检查训练进程
    TRAIN_PROCESS=$(ps aux | grep "lerobot-train" | grep -v grep | wc -l)
    
    # 检查最新的评估日志
    LATEST_EVAL_LOG=$(ls -t logs/*eval*.log 2>/dev/null | head -1)
    if [ -n "$LATEST_EVAL_LOG" ]; then
        SUCCESS_RATE=$(grep "Success Rate:" "$LATEST_EVAL_LOG" | tail -1 | grep -oE "[0-9]+\.[0-9]+")
        if [ -n "$SUCCESS_RATE" ]; then
            echo "[$TIMESTAMP] 成功率: $SUCCESS_RATE%, 训练进程: $TRAIN_PROCESS" >> "$LOG_FILE"
            
            # 检查成功率是否<50%
            if (( $(echo "$SUCCESS_RATE < 50" | bc -l) )); then
                EVAL_PROCESS=$(ps aux | grep "scripts.eval" | grep -v grep | wc -l)
                
                if [ $TRAIN_PROCESS -eq 0 ] && [ $EVAL_PROCESS -eq 0 ]; then
                    echo "[$TIMESTAMP] ⚠️ 警告：成功率<50%且无进程运行！" >> "$LOG_FILE"
                fi
            fi
        fi
    fi
    
    # 每30分钟检查一次
    sleep 1800
done
