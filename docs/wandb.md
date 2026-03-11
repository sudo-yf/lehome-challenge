### Configure and Run Wandb Sweeps (Hyperparameter Optimization)

Source: https://context7.com/wandb/wandb/llms.txt

Defines a sweep configuration with various parameter types and search strategies, creates a sweep, and then launches an agent to execute the sweep. This enables automated hyperparameter tuning.

```python
import wandb

sweep_config = {
    "method": "bayes",  # "grid", "random", or "bayes"
    "metric": {
        "name": "val/accuracy",
        "goal": "maximize"
    },
    "parameters": {
        "learning_rate": {
            "distribution": "log_uniform_values",
            "min": 1e-5,
            "max": 1e-1
        },
        "batch_size": {
            "values": [16, 32, 64, 128]
        },
        "epochs": {
            "value": 10
        },
        "optimizer": {
            "values": ["adam", "sgd", "rmsprop"]
        }
    },
    "early_terminate": {
        "type": "hyperband",
        "min_iter": 3
    }
}

sweep_id = wandb.sweep(sweep_config, project="sweep-demo")

def train():
    with wandb.init() as run:
        config = run.config

        lr = config.learning_rate
        batch_size = config.batch_size

        for epoch in range(config.epochs):
            accuracy = 0.7 + epoch * 0.02 * (lr * 1000)
            run.log({"val/accuracy": accuracy, "epoch": epoch})

wandb.agent(sweep_id, function=train, count=20)
```

--------------------------------

### Initialize Wandb Run and Log Metrics

Source: https://github.com/wandb/wandb/blob/main/README.md

Initializes a Weights & Biases run, specifying the project name and configuration hyperparameters. It then logs sample metrics like accuracy and loss during the training process. The 'with' statement ensures the run is properly finished, even if errors occur.

```python
import wandb

# Project that the run is recorded to
project = "my-awesome-project"

# Dictionary with hyperparameters
config = {"epochs": 1337, "lr": 3e-4}

# The `with` syntax marks the run as finished upon exiting the `with` block,
# and it marks the run "failed" if there's an exception.
#
# In a notebook, it may be more convenient to write `run = wandb.init()`
# and manually call `run.finish()` instead of using a `with` block.
with wandb.init(project=project, config=config) as run:
    # Training code here

    # Log values to W&B with run.log()
    run.log({"accuracy": 0.9, "loss": 0.1})
```

--------------------------------

### Manage Hyperparameter Configuration with W&B

Source: https://context7.com/wandb/wandb/llms.txt

The `wandb.config` object stores and tracks hyperparameters and settings for your experiment. Values can be set at initialization or updated dynamically during the run.

```python
import wandb

with wandb.init(project="config-demo") as run:
    # Set config at initialization
    run.config.learning_rate = 0.001
    run.config.batch_size = 32

    # Update config with dictionary
    run.config.update({
        "epochs": 100,
        "optimizer": "adam",
        "model": {
            "type": "transformer",
            "layers": 6,
            "hidden_size": 512
        }
    })

    # Access config values
    lr = run.config.learning_rate
    print(f"Training with lr={lr}")

    # Config is also accessible via wandb.config global
    print(wandb.config.batch_size)
```

### Summary

Source: https://context7.com/wandb/wandb/llms.txt

The W&B SDK provides a comprehensive experiment tracking solution for machine learning workflows. The primary use cases include: (1) tracking training metrics and visualizing them in real-time dashboards, (2) versioning datasets and models with artifacts for reproducibility, (3) running hyperparameter sweeps with Bayesian optimization, and (4) collaborating with teams through shared workspaces and reports. The SDK integrates seamlessly with Jupyter notebooks, supports distributed training scenarios, and works in both online and offline modes.

--------------------------------

### Core APIs > wandb.config - Hyperparameter Configuration

Source: https://context7.com/wandb/wandb/llms.txt

The `wandb.config` object stores and tracks hyperparameters and settings for your experiment. You can set configuration values at initialization or update them later using the `update()` method. Config values can be accessed directly as attributes of the `run.config` object or through the global `wandb.config`.


## LeHome Repo Sweep Workflow

`docs/wandb.md` 上面的内容是 W&B 官方式通用示例；在本仓库里，当前 sweep 已经重建为**官方 W&B function-based flow**：
- `lehome/wandb.sh`：只做 WandB 预检，并优先读取 `WANDB_ENV_FILE`
- `lehome/sweep.sh`：对外壳入口，负责环境整理、`--preflight` / `--dry-run` / 正式启动
- `scripts/wandb_repro.py`：正式科研可复现模式所需的代码快照、数据清单、环境清单与一致性校验工具
- `scripts/wandb_sweep.py`：正式的 sweep 主入口，内部直接走 `wandb.sweep(...)` + `wandb.agent(..., function=train)`
- `scripts/wandb_preflight.py`：轻量在线预检

### Repository-specific differences you need to know

- 现在的正式实现不再依赖 `command/program` 注入，也不再依赖 `WANDB_SWEEP_PARAM_PATH` 中转；每个 trial 都在 `train()` 里自己 `wandb.init()`，再直接调用 LeRobot 训练。
- sweep 超参数统一使用 W&B 页面可直接显示的扁平键：`batch_size`、`steps`、`log_freq`、`policy_optimizer_lr`、`policy_optimizer_weight_decay`、`policy_scheduler_warmup_steps`。
- 这些扁平键会直接保留在 `wandb.config` 中，因此 Runs 表格可以直接添加 `config.policy_optimizer_lr`、`config.policy_optimizer_weight_decay`、`config.policy_scheduler_warmup_steps` 等列。
- 若未显式传入固定 `--job-name` / `JOB_NAME`，每个 run 会自动命名为“模型 + 关键超参数”形式，例如 `xvla_bs4_s100_lr3.09e-05_wd0_warm2000_log100`，便于在 W&B 页面直接区分。
- 为兼容已有配置文件，脚本仍接受旧写法（如 `policy.optimizer_lr`），但仓库内 sweep 配置文件已经改为推荐的扁平键 + `arg_name` 显式映射。
- `configs/sweeps/xvla_stage2.yaml` 现已切到“性能优先窄搜索”窗口：`batch_size=8`、`steps=30000`、`lr=1.3e-5~2.9e-5`、`warmup=1000`。
- `lehome/sweep.sh --preflight` / `PRECHECK=true` 仍然只做在线联通性验证，不创建 sweep。
- 若你只创建 sweep 不立即启动 agent，现在推荐使用 `--create-only`，后续再通过 `--sweep-id <id>` 重新接入同一个 sweep。

### Formal reproducibility mode

如果你需要的是**正式科研可复现模式**，请使用：
- `--repro-mode strict`：启用严格模式
- 默认要求 git 工作区干净；若只是开发期测试，可临时加 `--allow-dirty`
- sweep 创建时会先上传 4 类输入工件：
  - code snapshot artifact
  - dataset manifest artifact
  - environment manifest artifact
  - sweep manifest artifact
- agent 在每个 run 启动前都会验证：
  - git commit / dirty 状态
  - dataset hash
  - environment hash
- 若任一项不一致，run 会直接失败，不进入训练主循环

推荐命令：

```bash
HF_HUB_OFFLINE=1 TRANSFORMERS_OFFLINE=1 WANDB_DISABLE_ARTIFACT=true \
WANDB_ENV_FILE=/root/data/wandb.md SWEEP_CONFIG_PATH=configs/sweeps/xvla_stage2.yaml \
bash lehome/sweep.sh --model xvla --steps 100 --repro-mode strict --allow-dirty --create-only
```

随后用同一套环境变量接回：

```bash
HF_HUB_OFFLINE=1 TRANSFORMERS_OFFLINE=1 WANDB_DISABLE_ARTIFACT=true \
WANDB_ENV_FILE=/root/data/wandb.md SWEEP_CONFIG_PATH=configs/sweeps/xvla_stage2.yaml \
bash lehome/sweep.sh --model xvla --sweep-id <existing_sweep_id> --count 1 --repro-mode strict --allow-dirty
```

说明：
- 生产环境不建议使用 `--allow-dirty`。
- 当前仓库默认把 W&B 数据目录迁到：
  - `WANDB_DATA_DIR=/root/data/.cache/wandb-data`
  - `WANDB_ARTIFACT_DIR=/root/data/.cache/wandb-artifacts`
  以避免系统盘空间不足导致 artifact 失败。

### Recommended repo workflow

默认凭据来源建议使用 `WANDB_ENV_FILE`：
- 单行原始 token 文件，例如 `/root/data/wandb.md`
- 或标准 env 文件，例如 `WANDB_API_KEY=wandb_v1_...`

1. 先做基础预检：

```bash
WANDB_ENABLE=true WANDB_MODE=online WANDB_ENV_FILE=/root/data/wandb.md bash lehome/wandb.sh
```

2. 再做一次新的 API 在线预检：

```bash
PRECHECK=true WANDB_ENV_FILE=/root/data/wandb.md bash lehome/sweep.sh --model xvla
```

3. 先做一次 dry-run，确认 sweep 配置：

```bash
DRY_RUN=true SWEEP_CONFIG_PATH=configs/sweeps/xvla_stage2.yaml bash lehome/sweep.sh --model xvla --steps 100
```

4. 真正创建并启动 sweep：

```bash
WANDB_ENV_FILE=/root/data/wandb.md SWEEP_CONFIG_PATH=configs/sweeps/xvla_stage2.yaml bash lehome/sweep.sh --model xvla --count 8 --steps 3000
```

5. 如果只想先创建 sweep：

```bash
WANDB_ENV_FILE=/root/data/wandb.md CREATE_ONLY=true SWEEP_CONFIG_PATH=configs/sweeps/xvla_stage2.yaml bash lehome/sweep.sh --model xvla --steps 3000
```

6. 如果要稍后重新接入同一个 sweep：

```bash
WANDB_ENV_FILE=/root/data/wandb.md SWEEP_CONFIG_PATH=configs/sweeps/xvla_stage2.yaml bash lehome/sweep.sh --model xvla --sweep-id <existing_sweep_id> --count 4
```

### Common repo examples

当前推荐：
- 追求更低 `train/loss`：使用 `configs/sweeps/xvla_stage2.yaml`
- 优先稳定与较低显存风险：使用 `configs/sweeps/xvla_stage2_stable.yaml`

```bash
PRECHECK=true WANDB_ENV_FILE=/root/data/wandb.md bash lehome/sweep.sh --model xvla
DRY_RUN=true SWEEP_CONFIG_PATH=configs/sweeps/xvla_wandb.yaml bash lehome/sweep.sh --model xvla --steps 1000
WANDB_ENV_FILE=/root/data/wandb.md SWEEP_CONFIG_PATH=configs/sweeps/xvla_stage2.yaml bash lehome/sweep.sh --model xvla --count 12 --steps 3000
HF_HUB_OFFLINE=1 TRANSFORMERS_OFFLINE=1 WANDB_ENV_FILE=/root/data/wandb.md SWEEP_CONFIG_PATH=configs/sweeps/xvla_stage2.yaml bash lehome/sweep.sh --model xvla --count 1 --steps 100
```

## Local Sweep Snapshot (2026-03-11)

下面这份快照不是通用官方文档，而是基于当前仓库本机已经跑过的 XVLA WandB 训练产物整理出的结果摘要，用于回答两个实际问题：
- 目前本机跑出来的最佳超参数组合是什么。
- 下一轮 sweep 应该优先往哪个范围收窄。

### What this snapshot is based on

- 统计范围：`outputs/train/**/wandb/run-*/files/config.yaml` 与对应 `wandb-summary.json`
- 当前有效统计对象：`18` 个 XVLA WandB run
- 状态分布：`11` 个完成、`2` 个部分完成、`5` 个失败或无指标
- 排序指标：`train/loss`
- 排序依据与当前 sweep 目标一致，即最小化 `train/loss`

> Important: 这里的“最佳”是按训练指标 `train/loss` 定义，不是按统一 episode policy eval 排名定义。

### Step-normalized best runs (recommended definition of “best”)

更严谨的定义是：先固定训练步数预算，再在同一预算内比较 `train/loss`。也就是说，`100-step`、`1000-step`、`30000-step` 应分别排名，不能直接混成一个“全局最佳”。

当前本地产物里，能够基于 `wandb-summary.json` 做**严格终点比较**的预算只有：
- `100-step`
- `1000-step`
- `30000-step`

当前还**不能严格评出**的预算：
- `5000-step`：目前没有以 `5000` 为终点的独立 run，因此没有可直接对齐的 final summary
- `10000-step`：当前有 `4` 个配置为 `10000-step` 的 run，但 `wandb-summary.json` 里都没有有效指标
- `20000-step`：当前只有 `1` 个带指标的 run，但它只跑到了 `10300`，属于 partial，不构成严格同预算终点比较

如果后续想严格比较 `5000-step` 或 `10000-step`，建议在 sweep 过程中额外保留可导出的 step history（至少包括 `_step`、`train/steps`、`train/loss`），不要只依赖最终 `wandb-summary.json`。

> Recommended rule: 文档里若写“最佳超参数”，默认应理解为“在给定 step budget 下的最佳超参数”，而不是把 `100-step`、`1000-step`、`30000-step` 混排后的单一冠军。

### Exact same-budget winners from the current local snapshot

| Step Budget | Comparable Completed Runs | Best Run ID | Best train/loss | Batch Size | LR | Weight Decay | Warmup | Output Dir |
| --- | ---: | --- | ---: | ---: | ---: | ---: | ---: | --- |
| `100` | `5` | `dwgn9765` | `0.326171875` | `4` | `3.092009460289545e-05` | `0` | `2000` | `outputs/train/top_long/xvla_base_3w_steps_23` |
| `1000` | `5` | `gd0o7mhx` | `0.1650390625` | `8` | `1.7556102852931412e-05` | `0` | `1000` | `outputs/train/top_long/xvla_base_3w_steps_17` |
| `30000` | `1` | `6b0v9k76` | `0.0279541015625` | `8` | `2.723969611418414e-05` | `1.0e-4` | `1000` | `outputs/train/top_long/xvla_base_3w_steps_2` |

对应文件：
- `100-step` 最优配置：`outputs/train/top_long/xvla_base_3w_steps_22/wandb/run-20260311_012118-dwgn9765/files/config.yaml`
- `100-step` 最优指标：`outputs/train/top_long/xvla_base_3w_steps_22/wandb/run-20260311_012118-dwgn9765/files/wandb-summary.json`
- `1000-step` 最优配置：`outputs/train/top_long/xvla_base_3w_steps_17/wandb/run-20260310_155418-gd0o7mhx/files/config.yaml`
- `1000-step` 最优指标：`outputs/train/top_long/xvla_base_3w_steps_17/wandb/run-20260310_155418-gd0o7mhx/files/wandb-summary.json`
- `30000-step` 最优配置：`outputs/train/top_long/xvla_base_3w_steps_2/wandb/run-20260310_075626-6b0v9k76/files/config.yaml`
- `30000-step` 最优指标：`outputs/train/top_long/xvla_base_3w_steps_2/wandb/run-20260310_075626-6b0v9k76/files/wandb-summary.json`

### Global final-endpoint best (reference only, not apples-to-apples)

如果只是把当前所有已完成或已产出 summary 的 run 终点直接混在一起看，那么当前终点 loss 最低的是下面这组；但这只是**混合不同步数预算后的参考冠军**，不应替代上面的同预算比较。

| Item | Value |
| --- | --- |
| model | `xvla` |
| batch_size | `8` |
| steps | `30000` |
| policy.optimizer_lr | `2.723969611418414e-05` |
| policy.optimizer_weight_decay | `1.0e-4` |
| policy.scheduler_warmup_steps | `1000` |
| final train/loss | `0.0279541015625` |
| logged train/steps | `30000` |
| output_dir | `outputs/train/top_long/xvla_base_3w_steps_2` |
| run dir | `outputs/train/top_long/xvla_base_3w_steps_2/wandb/run-20260310_075626-6b0v9k76` |

对应文件：
- 配置记录：`outputs/train/top_long/xvla_base_3w_steps_2/wandb/run-20260310_075626-6b0v9k76/files/config.yaml`
- 指标摘要：`outputs/train/top_long/xvla_base_3w_steps_2/wandb/run-20260310_075626-6b0v9k76/files/wandb-summary.json`
- 最终 checkpoint：`outputs/train/top_long/xvla_base_3w_steps_2/checkpoints/030000/pretrained_model`

### YAMLs for replaying exact same-budget winners

#### `100-step` winner

推荐新建：
- `configs/sweeps/xvla_best_step100_local_20260311.yaml`

```yaml
name: xvla-best-step100-local-20260311
method: grid
project: lehome_xvla_sweep_stage2
metric:
  name: train/loss
  goal: minimize
parameters:
  batch_size:
    value: 4
  steps:
    value: 100
  log_freq:
    value: 100
  policy_optimizer_lr:
    arg_name: policy.optimizer_lr
    value: 3.092009460289545e-05
  policy_optimizer_weight_decay:
    arg_name: policy.optimizer_weight_decay
    value: 0.0
  policy_scheduler_warmup_steps:
    arg_name: policy.scheduler_warmup_steps
    value: 2000
```

```bash
WANDB_ENV_FILE=/root/data/wandb.md SWEEP_CONFIG_PATH=configs/sweeps/xvla_best_step100_local_20260311.yaml bash lehome/sweep.sh --model xvla --count 1
```

#### `1000-step` winner

推荐新建：
- `configs/sweeps/xvla_best_step1000_local_20260311.yaml`

```yaml
name: xvla-best-step1000-local-20260311
method: grid
project: lehome_xvla_sweep_stage2
metric:
  name: train/loss
  goal: minimize
parameters:
  batch_size:
    value: 8
  steps:
    value: 1000
  log_freq:
    value: 100
  policy_optimizer_lr:
    arg_name: policy.optimizer_lr
    value: 1.7556102852931412e-05
  policy_optimizer_weight_decay:
    arg_name: policy.optimizer_weight_decay
    value: 0.0
  policy_scheduler_warmup_steps:
    arg_name: policy.scheduler_warmup_steps
    value: 1000
```

```bash
WANDB_ENV_FILE=/root/data/wandb.md SWEEP_CONFIG_PATH=configs/sweeps/xvla_best_step1000_local_20260311.yaml bash lehome/sweep.sh --model xvla --count 1
```

#### `30000-step` winner

推荐新建：
- `configs/sweeps/xvla_best_step30000_local_20260311.yaml`

```yaml
name: xvla-best-step30000-local-20260311
method: grid
project: lehome_xvla_sweep_stage2
metric:
  name: train/loss
  goal: minimize
parameters:
  batch_size:
    value: 8
  steps:
    value: 30000
  log_freq:
    value: 1000
  policy_optimizer_lr:
    arg_name: policy.optimizer_lr
    value: 2.723969611418414e-05
  policy_optimizer_weight_decay:
    arg_name: policy.optimizer_weight_decay
    value: 1.0e-4
  policy_scheduler_warmup_steps:
    arg_name: policy.scheduler_warmup_steps
    value: 1000
```

```bash
WANDB_ENV_FILE=/root/data/wandb.md SWEEP_CONFIG_PATH=configs/sweeps/xvla_best_step30000_local_20260311.yaml bash lehome/sweep.sh --model xvla --count 1
```

### Full ranked run table

下表按 `train/loss` 从低到高排序；`partial` 表示 run 已经上报指标，但未跑满配置里的目标步数。

> Note: 这张表混合了不同 `steps` 预算，只适合作为全局参考，不适合作为严格意义上的“最佳超参数”定义。

| Rank | Run ID | Status | train/loss | Logged / Config Steps | Batch Size | LR | Weight Decay | Warmup | Output Dir |
| --- | --- | --- | ---: | --- | ---: | ---: | ---: | ---: | --- |
| 1 | `6b0v9k76` | `completed` | `0.027954102` | `30000 / 30000` | `8` | `2.723969611e-05` | `1.0e-4` | `1000` | `outputs/train/top_long/xvla_base_3w_steps_2` |
| 2 | `ngnn463t` | `partial` | `0.123046875` | `10300 / 20000` | `8` | `1.295851847e-05` | `1.0e-4` | `1000` | `outputs/train/top_long/xvla_base_3w_steps_18` |
| 3 | `gd0o7mhx` | `completed` | `0.165039062` | `1000 / 1000` | `8` | `1.755610285e-05` | `0` | `1000` | `outputs/train/top_long/xvla_base_3w_steps_17` |
| 4 | `c5absd01` | `completed` | `0.175781250` | `1000 / 1000` | `8` | `1.674868537e-05` | `1.0e-4` | `2000` | `outputs/train/top_long/xvla_base_3w_steps_16` |
| 5 | `kky8dunn` | `partial` | `0.193359375` | `4000 / 30000` | `8` | `1.243870529e-05` | `0` | `2000` | `outputs/train/top_long/xvla_base_3w_steps_3` |
| 6 | `nmbm3gt3` | `completed` | `0.230468750` | `1000 / 1000` | `8` | `1.135271798e-05` | `0` | `1000` | `outputs/train/top_long/xvla_base_3w_steps_9` |
| 7 | `ienoepcw` | `completed` | `0.244140625` | `1000 / 1000` | `8` | `1.084357496e-05` | `1.0e-4` | `2000` | `outputs/train/top_long/xvla_base_3w_steps_15` |
| 8 | `dwgn9765` | `completed` | `0.326171875` | `100 / 100` | `4` | `3.092009460e-05` | `0` | `2000` | `outputs/train/top_long/xvla_base_3w_steps_23` |
| 9 | `wofvizkn` | `completed` | `0.416015625` | `1000 / 1000` | `4` | `1.096325168e-05` | `0` | `1000` | `outputs/train/top_long/xvla_base_3w_steps_19` |
| 10 | `mkwfpdh8` | `completed` | `0.423828125` | `100 / 100` | `8` | `2.429859303e-05` | `0` | `2000` | `outputs/train/top_long/xvla_base_3w_steps_12` |
| 11 | `gfxnmqqy` | `completed` | `0.457031250` | `100 / 100` | `8` | `2.148530202e-05` | `0` | `2000` | `outputs/train/top_long/xvla_base_3w_steps_13` |
| 12 | `lcqvntb3` | `completed` | `0.781250000` | `100 / 100` | `8` | `1.234404910e-05` | `1.0e-4` | `2000` | `outputs/train/top_long/xvla_base_3w_steps_10` |
| 13 | `i22e9qsw` | `completed` | `0.800781250` | `100 / 100` | `8` | `1.008692223e-05` | `1.0e-4` | `1000` | `outputs/train/top_long/xvla_base_3w_steps_11` |
| 14 | `l72hj0tw` | `failed/no-metric` | - | `- / 10000` | `8` | `2.981977619e-05` | `1.0e-4` | `2000` | `outputs/train/top_long/xvla_base_3w_steps_8` |
| 15 | `u3pzeuob` | `failed/no-metric` | - | `- / 10000` | `8` | `3.074967707e-05` | `1.0e-4` | `2000` | `outputs/train/top_long/xvla_base_3w_steps_7` |
| 16 | `ftn9ec34` | `failed/no-metric` | - | `- / 10000` | `8` | `1.030885869e-05` | `1.0e-4` | `2000` | `outputs/train/top_long/xvla_base_3w_steps_6` |
| 17 | `0yrc7kuu` | `failed/no-metric` | - | `- / 10000` | `8` | `1.177757242e-05` | `1.0e-4` | `1000` | `outputs/train/top_long/xvla_base_3w_steps_4` |
| 18 | `ii0ycj6p` | `failed/no-metric` | - | `- / 30000` | `8` | `1.577903267e-05` | `1.0e-4` | `1000` | `outputs/train/top_long/xvla_base_3w_steps_5` |

### Patterns observed from the current runs

从当前本机结果里，可以先得到这些经验结论：

- 在现有样本中，`batch_size=8` 的最佳结果明显优于 `batch_size=4`
- 在现有样本中，`warmup=1000` 的最佳结果优于 `warmup=2000`
- `weight_decay=1.0e-4` 并不保证平均表现更好，但当前全局最优 run 正是 `1.0e-4`
- `lr` 太靠近 `3e-5` 时，`batch_size=8` 的多次 run 没有产出有效指标，说明高学习率区间的风险更高
- 当前最有希望的学习率带宽，落在大约 `1.3e-5 ~ 2.8e-5`

### Recommended next sweep ranges

#### Performance-first narrow sweep

如果目标是继续追更低的 `train/loss`，推荐下一轮优先收窄到：

```yaml
name: xvla-narrow-perf-20260311
method: bayes
project: lehome_xvla_sweep_stage2
metric:
  name: train/loss
  goal: minimize
parameters:
  batch_size:
    value: 8
  steps:
    value: 30000
  log_freq:
    value: 100
  policy_optimizer_lr:
    arg_name: policy.optimizer_lr
    distribution: log_uniform_values
    min: 1.3e-5
    max: 2.9e-5
  policy_optimizer_weight_decay:
    arg_name: policy.optimizer_weight_decay
    values: [0.0, 1.0e-4]
  policy_scheduler_warmup_steps:
    arg_name: policy.scheduler_warmup_steps
    values: [1000]
early_terminate:
  type: hyperband
  min_iter: 3
```

推荐保存为：
- `configs/sweeps/xvla_narrow_perf_20260311.yaml`

推荐命令：

```bash
WANDB_ENV_FILE=/root/data/wandb.md \
SWEEP_CONFIG_PATH=configs/sweeps/xvla_narrow_perf_20260311.yaml \
bash lehome/sweep.sh --model xvla --count 8
```

理由：
- 当前第 `1` 名与第 `2` 名都落在 `warmup=1000`
- 当前最佳完整 run 位于 `lr=2.72e-5`
- `lr≈3e-5` 附近已经出现多次无指标 run，不建议继续向上扩太多

#### Stability-first narrow sweep

如果目标是优先降低 OOM / 失败风险，推荐下一轮使用更保守的稳定窗口：

```yaml
name: xvla-narrow-safe-20260311
method: bayes
project: lehome_xvla_sweep_stage2
metric:
  name: train/loss
  goal: minimize
parameters:
  batch_size:
    value: 4
  steps:
    value: 20000
  log_freq:
    value: 100
  policy_optimizer_lr:
    arg_name: policy.optimizer_lr
    distribution: log_uniform_values
    min: 1.0e-5
    max: 1.6e-5
  policy_optimizer_weight_decay:
    arg_name: policy.optimizer_weight_decay
    values: [0.0, 1.0e-4]
  policy_scheduler_warmup_steps:
    arg_name: policy.scheduler_warmup_steps
    values: [1000]
early_terminate:
  type: hyperband
  min_iter: 3
```

推荐保存为：
- `configs/sweeps/xvla_narrow_safe_20260311.yaml`

推荐命令：

```bash
WANDB_ENV_FILE=/root/data/wandb.md \
SWEEP_CONFIG_PATH=configs/sweeps/xvla_narrow_safe_20260311.yaml \
bash lehome/sweep.sh --model xvla --count 8
```

理由：
- 仓库当前 stage2 overlay 已固定 `batch_size=4` 作为 24GB 显存上的稳妥设置
- 现有 agent 日志里已经出现过明确的 `CUDA OOM`
- 这套区间更偏“先稳定拿到可比 run，再进一步细化”

### Caveats and known differences

- 这里的最佳结果是基于 `train/loss`，不是基于统一 policy eval 成绩，因此仍然建议把最优 checkpoint 拿去做固定 episode 评估
- 当前仓库文档与仓库现状有一个值得注意的差异：`docs/training.md` 仍写着仓库未提供 XVLA 配置，但仓库实际上已经包含 `configs/train_xvla.yaml`，并且 `lehome/train.sh` 已支持 `xvla` 作为正式训练入口
- 当前 `docs/wandb.md` 与 `docs/wandb_sweep_runbook.md` 中提到的“`batch_size=4` 是 24GB 显存上的稳定值”仍然成立；这描述的是稳定默认值，不等于当前本机已经观测到的最佳结果

### Useful local artifact paths

- 最佳 run 配置：`outputs/train/top_long/xvla_base_3w_steps_2/wandb/run-20260310_075626-6b0v9k76/files/config.yaml`
- 最佳 run 指标：`outputs/train/top_long/xvla_base_3w_steps_2/wandb/run-20260310_075626-6b0v9k76/files/wandb-summary.json`
- 最佳 run 终点 checkpoint：`outputs/train/top_long/xvla_base_3w_steps_2/checkpoints/030000/pretrained_model`
- 24GB 机器上出现 OOM 的 agent 日志：`logs/wandb_agent_stage2_20260310_135123.log`

### No LeRobot patching

This repository automation does **not** modify any `lerobot` Python source files under `.venv/.../site-packages/lerobot/`. The sweep integration is implemented only in repository scripts and docs.
