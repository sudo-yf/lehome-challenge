# LeHome Challenge Workflow v2

`start/v2.0/` 是面向日常操作的轻量入口目录。

这里统一保留三类入口：
- 分步入口：`install.sh` / `finalize.sh` / `data.sh`
- 通用入口：`train.sh` / `eval.sh` / `save.sh` / `vpn.sh`
- 专用入口：`xvla.sh` / `wandb.sh` / `allinone.sh`

## 推荐顺序

1. `bash start/v2.0/vpn.sh`（可选，网络不稳时再开）
2. `bash start/v2.0/install.sh [--install-system-libs]`
3. `bash start/v2.0/finalize.sh`
4. `bash start/v2.0/data.sh [--with-full-dataset]`
5. `bash start/v2.0/train.sh ...`
6. `bash start/v2.0/eval.sh ...`
7. `bash start/v2.0/save.sh <version>`

XVLA 用户也可以直接跳到 `xvla.sh` 一体化入口；如果你更喜欢单一入口，也可以统一走 `allinone.sh`。

快速跑完整安装流程：

```bash
bash start/v2.0/setup.sh --install-system-libs --with-full-dataset
```

## 三步职责

- `install.sh`：安装前准备 + `uv sync` + IsaacLab + LeHome + `hf` + 核心导入校验
- `finalize.sh`：IsaacSim EULA、`_isaac_sim` 软链接、轻量 shell 快捷命令
- `data.sh`：Assets、合并数据集、可选完整 `dataset_challenge`

## 工具脚本

- `vpn.sh`：转发到仓库根目录 `start/step_vpn.sh`
- `train.sh`：转发到仓库根目录 `run_train.sh`
- `eval.sh`：转发到仓库根目录 `run_eval.sh`
- `save.sh`：转发到仓库根目录 `start/step_git.sh`
- `xvla.sh`：XVLA 专用 `install / train / eval` 一体脚本
- `wandb.sh`：WandB 环境变量预检脚本，只做检查与展示，不启动训练
- `allinone.sh`：统一分发入口，可转发到 `setup / install / finalize / data / train / eval / xvla / wandb / save / vpn`

## `just` 用法

进入 `start/v2.0/` 后可以直接使用：

```bash
cd start/v2.0
just install --install-system-libs
just finalize
just data --with-full-dataset
just train act 1000
just eval act
just xvla
just wandb
just allinone setup --install-system-libs --with-full-dataset
just save 1
```

说明：
- `just install / finalize / data` 是主名字
- `just train` / `just eval` 走的是通用包装脚本 `train.sh` / `eval.sh`
- `just xvla` 只是执行 `bash xvla.sh`，配置仍主要来自环境变量和脚本顶部默认值
- `just wandb` 会执行独立的 `wandb.sh` 预检
- `just allinone ...` 会统一转发到 `allinone.sh`

## All-in-One 入口

`allinone.sh` 是统一入口，适合想记一个命令的人。

支持的命令：
- `setup`
- `install`
- `finalize`
- `data`
- `train`
- `eval`
- `xvla`
- `wandb`
- `vpn`
- `save`

最小示例：

```bash
bash start/v2.0/allinone.sh setup --install-system-libs --with-full-dataset
bash start/v2.0/allinone.sh install --install-system-libs
bash start/v2.0/allinone.sh train act 1000
bash start/v2.0/allinone.sh xvla
```

## XVLA 一体脚本

`xvla.sh` 是 XVLA 专用入口，支持：
- `WORK_MODE=install`
- `WORK_MODE=train`
- `WORK_MODE=eval`

默认情况下，训练相关默认值会从 `configs/train_xvla.yaml` 自动读取，包括：
- `dataset.repo_id`
- `dataset.root`
- `policy.repo_id`
- `policy.pretrained_path`
- `output_dir`
- `steps`

训练模式额外支持这些环境变量覆盖：
- `JOB_NAME`
- `DRY_RUN`
- `HF_TOKEN`
- `DATASET_REPO`
- `DATASET_ROOT`
- `MY_ROBOT_REPO`
- `PRETRAINED_PATH`
- `OUTPUT_DIR`
- `TRAIN_STEPS`

补充说明：
- `DRY_RUN=true` 只生成临时 YAML，并打印最终 `lerobot-train --config_path=...` 命令，不真正启动训练
- 训练模式会在临时配置里写入当前生效的 `wandb` 配置
- 评估模式仍按现有流程执行，不会通过 `wandb.sh` 单独上报评估结果

最小示例：

```bash
WORK_MODE=train DRY_RUN=true bash start/v2.0/xvla.sh
WORK_MODE=train JOB_NAME=xvla_top_long WANDB_ENABLE=true WANDB_MODE=offline bash start/v2.0/xvla.sh
WORK_MODE=eval GARMENT_TYPE=top_long EVAL_EPISODES=5 bash start/v2.0/xvla.sh
```

## WandB 预检

`wandb.sh` 只负责检查并展示当前最终生效的 WandB 配置，不负责启动训练。

支持的环境变量：
- `WANDB_ENABLE`
- `WANDB_MODE`
- `WANDB_PROJECT`
- `WANDB_ENTITY`
- `WANDB_NOTES`
- `WANDB_RUN_ID`
- `WANDB_DISABLE_ARTIFACT`
- `WANDB_API_KEY`

当前模式行为：
- `WANDB_MODE=disabled`：允许执行，但训练配置会写成 `wandb.enable=false`
- `WANDB_MODE=offline`：要求当前 `.venv` 中可导入 `wandb`
- `WANDB_MODE=online`：除可导入 `wandb` 外，还要求设置 `WANDB_API_KEY`

最小示例：

```bash
WANDB_ENABLE=false bash start/v2.0/wandb.sh
WANDB_ENABLE=true WANDB_MODE=offline bash start/v2.0/wandb.sh
WANDB_ENABLE=true WANDB_MODE=online WANDB_API_KEY=*** bash start/v2.0/wandb.sh
```

安全说明：
- W&B API key 只通过环境变量传入
- 不要把 key 写进仓库、README、脚本或日志

## 进阶入口

如需自动化超参搜索，可查看 `scripts/wandb_sweep.py`。
