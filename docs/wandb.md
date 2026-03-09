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

`docs/wandb.md` 上面的内容是 W&B 官方式通用示例；在本仓库里，自动调参与预检的正式入口是：
- `lehome/wandb.sh`：只做 WandB 预检，并会优先读取 `WANDB_ENV_FILE`（默认 `/root/data/wandb.env`）
- `lehome/sweep.sh`：创建 / 启动 sweep，也支持新的 `--preflight` 预检模式
- `scripts/wandb_sweep.py`：生成 sweep config，并调用 `wandb.sweep(...)` 与 `wandb.agent(...)`
- `scripts/wandb_preflight.py`：使用新的 `wandb.init()` API 做轻量在线预检

### Repository-specific differences you need to know

- `scripts/wandb_sweep.py` 不再只传 `--wandb.enable=true`，还会显式传 `--wandb.mode=online`。这是因为 `configs/train_xvla.yaml` 默认写了 `wandb.mode: disabled`；如果不覆盖，sweep 虽然能创建，但训练侧不会真正把指标上报到 W&B。
- `scripts/wandb_sweep.py` 现在还会把像 `policy.optimizer_lr` 这样的 LeRobot 参数名自动规范化成 W&B 可接受的 sweep 参数名（例如 `policy_optimizer_lr`），并在 `command` 里显式展开回 `--policy.optimizer_lr=...`。这是为了解决 W&B API 对超参数名校验更严格时的 400 错误。
- 当你用 `configs/sweeps/xvla_stage2.yaml` 这类 overlay 覆盖默认 sweep 参数时，仓库现在会把单个参数块按“整体替换”处理，而不是递归合并。这样可以避免生成非法配置，例如 `batch_size` 同时带 `values` 和 `value`，进而触发 `Invalid sweep config: invalid hyperparameter configuration: batch_size`。
- `lehome/sweep.sh --preflight` / `PRECHECK=true` 会先跑一个轻量 online run，验证 key、project、entity 与同步链路，再退出；它不会创建 sweep。
- sweep 的目标指标默认使用 LeRobot 训练里实际会上报的 `train/loss`。
- 需要给训练额外透传参数时，不直接改 `command`，而是通过 `lehome/sweep.sh ... -- <train-args>` 或 `scripts/wandb_sweep.py --train-arg ...` 追加到当前训练入口 `lehome/train.sh`。

### Recommended repo workflow

默认凭据来源建议使用 `WANDB_ENV_FILE`：
- 单行原始 token 文件，例如当前的 `/root/data/wandb.md`
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
DRY_RUN=true SWEEP_CONFIG_PATH=configs/sweeps/xvla_wandb.yaml bash lehome/sweep.sh --model xvla --steps 1000
```

4. 真正创建并启动 sweep：

```bash
WANDB_ENV_FILE=/root/data/wandb.md bash lehome/sweep.sh --model xvla --count 8 --steps 3000
```

5. 如果只想先创建 sweep，再手动起 agent：

```bash
WANDB_ENV_FILE=/root/data/wandb.md CREATE_ONLY=true bash lehome/sweep.sh --model xvla --steps 3000
```

### Common repo examples

可选地，也可以把 sweep 搜索空间写进 `configs/sweeps/xvla_wandb.yaml`，再通过 `SWEEP_CONFIG_PATH=...` 载入。

Stage 2 长训建议使用单独 overlay，例如 `configs/sweeps/xvla_stage2.yaml`；这类文件里的参数块（如 `batch_size`、`steps`）会整体覆盖默认模板，而不是和默认值混合。

```bash
PRECHECK=true WANDB_ENV_FILE=/root/data/wandb.md bash lehome/sweep.sh --model xvla
WANDB_ENV_FILE=/root/data/wandb.md bash lehome/sweep.sh --model xvla --count 12 --steps 3000
WANDB_ENV_FILE=/root/data/wandb.md WANDB_PROJECT=lehome_xvla_sweep_top_long bash lehome/sweep.sh --model xvla --count 8 --steps 5000
DRY_RUN=true SWEEP_CONFIG_PATH=configs/sweeps/xvla_wandb.yaml bash lehome/sweep.sh --model xvla --steps 1000 -- --job_name=xvla_sweep_top_long
```

### No LeRobot patching

This repository automation does **not** modify any `lerobot` Python source files under `.venv/.../site-packages/lerobot/`. The sweep integration is implemented only in repository scripts and docs.
