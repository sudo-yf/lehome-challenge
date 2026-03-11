# WandB Sweep Runbook for LeHome (Official Function Mode)

这份 runbook 记录当前仓库里已经切换完成的 sweep 运行方式：
- 对外入口仍是 `lehome/sweep.sh` / `just sweep`
- 内部已经改成官方 W&B function-based flow：`wandb.sweep(...)` + `wandb.agent(..., function=train)`
- 每个 trial 在 Python `train()` 中自己 `wandb.init()`，直接读取 `run.config` 并调用 LeRobot 训练

## 1. 当前实现要点

- `scripts/wandb_sweep.py` 是正式主入口。
- sweep 超参数统一使用 W&B 页面可见的扁平键：
  - `batch_size`
  - `steps`
  - `log_freq`
  - `policy_optimizer_lr`
  - `policy_optimizer_weight_decay`
  - `policy_scheduler_warmup_steps`
- run 默认自动命名为“模型 + 关键超参数”形式，便于直接在 W&B 页面区分。
- `--create-only` 只创建 sweep，不启动 agent；后续通过 `--sweep-id <id>` 重新接入。

## 2. 推荐命令

### 2.1 预检

```bash
PRECHECK=true WANDB_ENV_FILE=/root/data/wandb.md bash lehome/sweep.sh --model xvla
```

### 2.2 dry-run

```bash
DRY_RUN=true SWEEP_CONFIG_PATH=configs/sweeps/xvla_stage2.yaml bash lehome/sweep.sh --model xvla --steps 100
```

### 2.3 正式创建并运行

```bash
WANDB_ENV_FILE=/root/data/wandb.md SWEEP_CONFIG_PATH=configs/sweeps/xvla_stage2.yaml bash lehome/sweep.sh --model xvla --count 8 --steps 3000
```

### 2.3b XVLA 30k 内置 Eval 窄 sweep

```bash
WANDB_ENV_FILE=/root/data/wandb.md \
TRAIN_CONFIG_PATH=configs/train_xvla_30k_better_than_baseline.yaml \
SWEEP_CONFIG_PATH=configs/sweeps/xvla_wandb_eval_narrow.yaml \
bash lehome/sweep.sh --model xvla --count 8
```

### 2.4 只创建

```bash
WANDB_ENV_FILE=/root/data/wandb.md CREATE_ONLY=true SWEEP_CONFIG_PATH=configs/sweeps/xvla_stage2.yaml bash lehome/sweep.sh --model xvla --steps 3000
```

### 2.5 接回已有 sweep

```bash
WANDB_ENV_FILE=/root/data/wandb.md SWEEP_CONFIG_PATH=configs/sweeps/xvla_stage2.yaml bash lehome/sweep.sh --model xvla --sweep-id <existing_sweep_id> --count 4
```

## 3. 页面检查点

在 W&B Runs 表格中，直接检查这些列：
- `config.batch_size`
- `config.steps`
- `config.policy_optimizer_lr`
- `config.policy_optimizer_weight_decay`
- `config.policy_scheduler_warmup_steps`
- `config.policy_scheduler_decay_steps`
- `config.policy_scheduler_decay_lr`
- `eval/pc_success`
- `eval/avg_sum_reward`

推荐按下面任一字段着色：
- `config.policy_scheduler_warmup_steps`
- `config.policy_optimizer_weight_decay`

## 4. 本机注意事项

- `configs/sweeps/xvla_stage2.yaml` 当前是“性能优先窄搜索”默认配置：`batch_size=8`、`steps=30000`、`lr=1.3e-5~2.9e-5`、`warmup=1000`。
- `configs/sweeps/xvla_stage2_stable.yaml` 是“稳定优先”备选配置：`batch_size=4`、`steps=20000`、`lr=1.0e-5~1.6e-5`、`warmup=1000`。
- `configs/train_xvla_30k_better_than_baseline.yaml` 会启用训练内 LeHome eval；它依赖 `scripts/lerobot_train_lehome.py` 先启动 IsaacLab App，再进入 LeRobot 训练。
- `configs/sweeps/xvla_wandb_eval_narrow.yaml` 以 `eval/pc_success` 为主指标，适合做 30k 证据收窄筛选；最终模型仍建议走外部 `just eval` 复核。
- 若 Hugging Face 在线探测拖慢启动，建议使用：

```bash
HF_HUB_OFFLINE=1 TRANSFORMERS_OFFLINE=1 ...
```

- 当前实现不修改 `.venv/.../site-packages/lerobot/`。


## 5. 正式科研可复现模式

严格模式入口：
- `--repro-mode strict`
- 开发期测试可临时加 `--allow-dirty`，正式实验不建议

严格模式会在创建 sweep 前生成并上传：
- code snapshot artifact
- dataset manifest artifact
- environment manifest artifact
- sweep manifest artifact

每个 agent trial 启动前都会校验：
- git commit / dirty 状态
- dataset hash
- environment hash

若校验失败，run 会直接失败，不进入训练。

当前建议同时设置：

```bash
HF_HUB_OFFLINE=1
TRANSFORMERS_OFFLINE=1
WANDB_DATA_DIR=/root/data/.cache/wandb-data
WANDB_ARTIFACT_DIR=/root/data/.cache/wandb-artifacts
```
