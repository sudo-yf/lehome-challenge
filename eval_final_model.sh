#!/bin/bash
# 评估最终训练的模型

cd /root/data/lehome-challenge

# 使用训练好的模型进行评估
/root/data/lehome-challenge/.venv/bin/python -m scripts.eval \
    --policy_type lerobot \
    --policy_path outputs/train/top_long/xvla_base_3w_steps_final/checkpoints/last/pretrained_model \
    --garment_type "top_long" \
    --dataset_root Datasets/example/top_long_merged \
    --num_episodes 2 \
    --enable_cameras \
    --device cpu \
    --save_video \
    --video_dir outputs/eval_videos_final

echo "评估完成！查看日志获取Success Rate"
