#!/bin/bash
cd /root/data/lehome-challenge

# 检查是否有评估结果
LATEST_LOG=$(ls -t logs/*eval*.log 2>/dev/null | head -1)
if [ -n "$LATEST_LOG" ]; then
    SUCCESS_RATE=$(grep "Success Rate:" "$LATEST_LOG" | tail -1 | grep -oE "[0-9]+\.[0-9]+")
    if [ -n "$SUCCESS_RATE" ]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] 最新成功率: $SUCCESS_RATE%" >> logs/cron_check.log
        
        # 如果成功率<50%，记录警告
        if (( $(echo "$SUCCESS_RATE < 50" | bc -l) )); then
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] ⚠️ 警告：成功率低于50%！" >> logs/cron_check.log
        fi
    fi
fi
