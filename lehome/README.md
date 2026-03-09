# LeHome 主入口手册

`lehome/` 是当前项目的主力脚本目录。

设计目标：
- 让常用入口尽量少
- 把“环境准备 / 数据下载 / 训练 / 评估 / XVLA / WandB”收进统一结构
- 不改底层真实训练与评估命令，只改外层入口、展示和检查逻辑

## 目录结构

当前主入口文件：
- `allinone.sh`：统一总入口
- `prepare.sh`：环境准备
- `data.sh`：数据下载
- `train.sh`：训练包装入口
- `eval.sh`：评估包装入口
- `xvla.sh`：XVLA 专用入口
- `wandb.sh`：WandB 预检
- `sweep.sh`：WandB sweep 入口
- `common.sh`：公共辅助函数
- `justfile`：目录内快捷命令

历史备份：
- `v1/`：原始 `start/step*.sh` 备份，不再作为主入口

## 推荐顺序

### 常规流程

1. `bash lehome/allinone.sh vpn`（可选）
2. `bash lehome/allinone.sh prepare [--install-system-libs]`
3. `bash lehome/allinone.sh data [--with-full-dataset]`
4. `bash lehome/allinone.sh train ...`
5. `bash lehome/allinone.sh eval ...`
6. `bash lehome/allinone.sh save <version>`

### 一次性准备

```bash
bash lehome/allinone.sh setup --install-system-libs --with-full-dataset
```

## 脚本职责

### `allinone.sh`

统一分发入口，支持：
- `setup`
- `prepare`
- `data`
- `train`
- `eval`
- `xvla`
- `wandb`
- `sweep`
- `vpn`
- `save`

适合：
- 想记最少命令的人
- 希望所有动作都从一个脚本进入的人

### `prepare.sh`

负责环境准备，包含：
- `uv sync`
- IsaacLab / LeHome / HuggingFace CLI 安装
- 核心导入校验
- IsaacSim EULA 授权
- `_isaac_sim` 软链接
- shell 快捷命令写入

常用示例：

```bash
bash lehome/prepare.sh --install-system-libs
```

### `data.sh`

负责数据资源下载，包含：
- `Assets`
- 合并版示例数据集
- 可选完整 `dataset_challenge`

常用示例：

```bash
bash lehome/data.sh --with-full-dataset
```

### `train.sh` / `eval.sh`

这两个只是包装层：
- `train.sh` -> 仓库根目录 `run_train.sh`
- `eval.sh` -> 仓库根目录 `run_eval.sh`

也就是说：
- 新入口目录变了
- 真实训练 / 评估逻辑没变

### `xvla.sh`

这是 XVLA 专用入口，支持：
- `WORK_MODE=install`
- `WORK_MODE=train`
- `WORK_MODE=eval`

默认会从 `configs/train_xvla.yaml` 自动读取：
- `dataset.repo_id`
- `dataset.root`
- `policy.repo_id`
- `policy.pretrained_path`
- `output_dir`
- `steps`

训练模式常见可覆盖环境变量：
- `JOB_NAME`
- `DRY_RUN`
- `HF_TOKEN`
- `DATASET_REPO`
- `DATASET_ROOT`
- `MY_ROBOT_REPO`
- `PRETRAINED_PATH`
- `OUTPUT_DIR`
- `TRAIN_STEPS`

示例：

```bash
WORK_MODE=train DRY_RUN=true bash lehome/xvla.sh
WORK_MODE=train JOB_NAME=xvla_top_long WANDB_ENABLE=true WANDB_MODE=offline bash lehome/xvla.sh
WORK_MODE=eval GARMENT_TYPE=top_long EVAL_EPISODES=5 bash lehome/xvla.sh
```

### `wandb.sh`

只做 WandB 预检，不直接启动训练。

支持环境变量：
- `WANDB_ENABLE`
- `WANDB_MODE`
- `WANDB_PROJECT`
- `WANDB_ENTITY`
- `WANDB_NOTES`
- `WANDB_RUN_ID`
- `WANDB_DISABLE_ARTIFACT`
- `WANDB_API_KEY`
- `WANDB_ENV_FILE`（默认 `/root/data/wandb.env`）

行为约束：
- `WANDB_MODE=disabled`：训练配置会写成 `wandb.enable=false`
- `WANDB_MODE=offline`：要求当前 `.venv` 中能导入 `wandb`
- `WANDB_MODE=online`：要求能导入 `wandb`，且必须设置 `WANDB_API_KEY`

示例：

```bash
WANDB_ENABLE=false bash lehome/wandb.sh
WANDB_ENABLE=true WANDB_MODE=offline bash lehome/wandb.sh
WANDB_ENABLE=true WANDB_MODE=online WANDB_ENV_FILE=/root/data/wandb.md bash lehome/wandb.sh
```

### `sweep.sh`

负责 WandB sweep 自动调参入口，底层调用：
- `scripts/wandb_sweep.py`

约束：
- 默认要求 `WANDB_ENABLE=true`
- 非 `DRY_RUN=true` 时要求 `WANDB_MODE=online`
- 非 `DRY_RUN=true` 时要求能拿到 `WANDB_API_KEY`（可直接传，或通过 `WANDB_ENV_FILE` 加载）
- `--preflight` / `PRECHECK=true` 会用新的 `wandb.init()` API 做一次在线预检 run，然后退出，不创建 sweep

示例：

```bash
PRECHECK=true WANDB_ENV_FILE=/root/data/wandb.md bash lehome/sweep.sh --model xvla
WANDB_ENV_FILE=/root/data/wandb.md bash lehome/sweep.sh --model xvla --count 8 --steps 3000
WANDB_ENV_FILE=/root/data/wandb.md CREATE_ONLY=true bash lehome/sweep.sh --model xvla --steps 3000
DRY_RUN=true SWEEP_CONFIG_PATH=configs/sweeps/xvla_wandb.yaml bash lehome/sweep.sh --model xvla --steps 1000 -- --job_name=xvla_sweep_top_long
```

## `just` 用法

进入 `lehome/` 后可以直接使用：

```bash
cd lehome
just prepare --install-system-libs
just data --with-full-dataset
just train act 1000
just eval act
just xvla
just wandb
just sweep --preflight --model xvla
just sweep --dry-run --model xvla --steps 1000
just setup --install-system-libs --with-full-dataset
just save 1
```

说明：
- `just` 统一走当前目录下的新入口
- `train` / `eval` 仍会调用仓库根目录真实脚本
- `xvla` / `wandb` / `sweep` 是专用入口

## 你什么时候看 `v1/`

只有在下面场景才需要：
- 想回看原始 `start/step*.sh` 的旧行为
- 想对照这次入口改造前后的结构差异
- 需要临时参考旧版命名和脚本职责

平时开发和运行，直接忽略 `v1/` 即可。
