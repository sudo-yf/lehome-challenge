>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


本篇文档将分别用实例展示 WandB 和 SwanLab 的基本使用方法。

WandB
官方快速开始文档：wandb/quickstart

说明：直接访问 WandB 的云端 API 可能出现网络超时、连接失败等问题。建议使用英博云学术加速服务。参考：学术加速

安装 wandb 并登录


pip install wandb -i https://pypi.tuna.tsinghua.edu.cn/simple
wandb login
如果希望每次都免密登录，全局设置 WANDB_API_KEY 环境变量，即 wandb 登录密钥。


export WANDB_API_KEY=<your_api_key>
API key 的位置在：wandb/api_key

W&B 实验流程包括：使用 init 初始化实验，config 配置超参数，log 分组记录指标，必要时通过 alert 发送告警，最终在 summary 汇总结果并以 finish 结束实验。

参考：wandb/create-an-experiment

以下是一个随机数模拟的可直接运行的 WandB 示例，将其保存为 test.py，并运行 python test.py。


import random
import wandb

# Launch 5 simulated experiments
total_runs = 5
for run in range(total_runs):
  # Start a new run to track this script
  wandb.init(
      # Set the project where this run will be logged
      project="wandbexample1",
      # We pass a run name (otherwise it’ll be randomly assigned, like sunshine-lollypop-10)
      name=f"experiment_{run}",
      # Track hyperparameters and run metadata
      config={
      "learning_rate": 0.02,
      "architecture": "CNN",
      "dataset": "CIFAR-100",
      "epochs": 10,
      })

  # This simple block simulates a training loop logging metrics
  epochs = 10
  offset = random.random() / 5
  for epoch in range(2, epochs):
      acc = 1 - 2 ** -epoch - random.random() / epoch - offset
      loss = 2 ** -epoch + random.random() / epoch + offset

      # Log metrics from your script to W&B
      wandb.log({"acc": acc, "loss": loss})

  # Mark the run as finished
  wandb.finish()
运行之后会出现以下选择


wandb: (1) Create a W&B account
wandb: (2) Use an existing W&B account
wandb: (3) Don't visualize my results
如果是初次使用 wandb，选择 1，创建新的界面，后续可以按需选择。

成功运行后会在终端打印浏览器链接，点击可直达 WandB 可视化界面。


# uv + wandb 中文技能（高信息密度版）

## 0. 使用方式

执行此技能时，遵循以下顺序：

1. 先识别用户请求属于 `uv`、`wandb`，还是二者联动。
2. 先给最小可运行命令/代码，再给扩展方案。
3. 明确标注来源文件（`docs/...`）。
4. 若用户提到安装/环境/部署，优先给操作步骤和排错清单。
5. 若用户提到“调参/超参/搜索”，优先进入 Sweeps 模块（重点）。

输出风格要求：

- 使用中文。
- 优先可复制命令。
- 每段方案结尾给“适用场景”。
- 不省略关键参数含义。

---

## 1. 文档清单（全覆盖）

### uv 目录

- `docs/uv/01-overview.md`
- `docs/uv/02-projects.md`
- `docs/uv/03-commands.md`
- `docs/uv/04-environments.md`
- `docs/uv/05-workspaces-tools.md`
- `docs/uv/06-configuration.md`
- `docs/uv/07-docker-cicd.md`

### wandb 目录

- `docs/wandb/01-overview.md`
- `docs/wandb/02-logging-tracking.md`
- `docs/wandb/03-artifacts.md`
- `docs/wandb/04-sweeps.md`（重点）
- `docs/wandb/05-reports-viz.md`
- `docs/wandb/06-integrations.md`
- `docs/wandb/07-api-config.md`
- `docs/wandb/08-alerts-registry.md`

---

## 2. 重点一：`docs/uv/01-overview.md`（安装与入门）

本文件是所有 uv 对话的首入口。只要用户问“如何装 uv / uv 怎么开始 / 容器里装 uv”，优先使用这里的内容。

### 2.1 安装脚本帮助（先看参数）

```bash
curl -LsSf https://astral.sh/uv/install.sh | sh -s -- --help
```

解释：

- `curl -LsSf`：静默下载，失败时返回非 0。
- `sh -s -- --help`：将 `--help` 传递给安装脚本。
- 适用场景：用户不确定安装参数、需要自定义安装行为。

### 2.2 Linux / Docker 中安装 uv（官方安装器）

```Dockerfile
FROM python:3.12-slim-trixie

# 安装器依赖 curl 和证书
RUN apt-get update && apt-get install -y --no-install-recommends curl ca-certificates

# 获取并执行安装脚本
ADD https://astral.sh/uv/install.sh /uv-installer.sh
RUN sh /uv-installer.sh && rm /uv-installer.sh

# 让 uv 进入 PATH
ENV PATH="/root/.local/bin/:$PATH"
```

解释：

- `curl` / `ca-certificates` 是安装器必要依赖。
- 安装后通常在 `/root/.local/bin`，必须加入 `PATH`。
- 适用场景：容器镜像内构建、CI 基础镜像。

### 2.3 Windows 安装（winget）

```bash
winget install --id=astral-sh.uv -e
```

解释：

- `-e` 表示精确匹配 ID。
- 适用场景：Windows 开发机标准安装。

### 2.4 PyPI 隔离安装（pipx）

```bash
pipx install uv
```

解释：

- 在隔离环境安装 uv，避免污染项目依赖。
- 适用场景：已使用 `pipx` 管理 CLI 工具。

### 2.5 安装后建议的最小验证流程（补充执行规范）

虽然该文件未给出验证命令，但执行层建议固定补 3 步：

```bash
uv --version
uv venv
uv pip sync requirements.txt
```

解释：

- `uv --version` 验证可执行文件可见。
- `uv venv` 验证 Python 与 venv 工作正常。
- `uv pip sync` 验证依赖求解与安装链路。

### 2.6 安装常见故障与处置（高频）

1. `curl: command not found`
- 原因：基础镜像太小。
- 处置：安装 `curl` 与证书包。

2. `uv: command not found`
- 原因：PATH 未包含 `/root/.local/bin`。
- 处置：在 shell 或 Dockerfile 增加 PATH。

3. Windows 无 `winget`
- 处置：改用 `pipx install uv`，或使用官方安装脚本流程。

4. 容器内网络证书错误
- 处置：确保安装 `ca-certificates`，并刷新证书。

### 2.7 当用户只问“给我一个安装命令”时的默认答复模板

- Linux/macOS：

```bash
curl -LsSf https://astral.sh/uv/install.sh | sh
```

- Windows：

```bash
winget install --id=astral-sh.uv -e
```

- 有 `pipx`：

```bash
pipx install uv
```

---

## 3. 重点二：`docs/wandb/04-sweeps.md`（超参数搜索）

只要用户问“调参、超参搜索、bayes/grid/random、批量实验”，优先使用本节。

### 3.1 Sweeps 最小工作流

1. 定义 `sweep_config`。
2. 调用 `wandb.sweep(...)` 创建 sweep 并拿到 `sweep_id`。
3. 编写 `train()`，内部用 `with wandb.init()`。
4. 在 `train()` 中从 `run.config` 读取超参数。
5. 通过 `run.log()` 记录目标指标。
6. 用 `wandb.agent(...)` 执行多次实验。

### 3.2 参考配置（原文核心）

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

### 3.3 `sweep_config` 字段说明（必须解释）

- `method`
- 可选：`grid`、`random`、`bayes`。
- 典型选择：
  - 参数空间小且离散：`grid`
  - 先快速探索：`random`
  - 预算有限且要效率：`bayes`

- `metric.name`
- 指定优化目标的日志 key。
- 必须与 `run.log()` 中字段一致。

- `metric.goal`
- `maximize` 或 `minimize`。
- 与指标语义匹配，例如准确率通常最大化，loss 通常最小化。

- `parameters`
- 支持 `value`（固定值）、`values`（离散集合）、`distribution + min/max`（连续采样）。

- `early_terminate`
- 示例为 `hyperband`。
- `min_iter` 用于早停控制，避免低质量配置浪费预算。

### 3.4 关键一致性检查（非常重要）

1. `metric.name` 与 `run.log` 键一致。
- 若 `metric.name` 为 `val/accuracy`，日志必须记录 `{"val/accuracy": ...}`。

2. `train()` 里使用 `with wandb.init()`。
- 不要在 sweep 训练函数外部复用旧 run。

3. 从 `run.config` 读取参数。
- 不要把 sweep 参数写死到函数内。

4. 设定 `count`。
- 便于控制预算和总运行数量。

### 3.5 Sweeps 常见失败模式与修复

1. 指标无曲线或优化目标无效
- 通常是 `metric.name` 和 `run.log` 键名不一致。

2. 参数没有变化
- 通常是没有使用 `run.config`，而是写了固定常量。

3. sweep 运行数量失控
- 忘了 `count`，或 agent 分发策略不清晰。

4. 训练报错但 sweep 继续
- 在 `train()` 内加异常捕获并记录错误上下文。

### 3.6 可复用 Sweeps 模板（建议直接给用户）

```python
import wandb

SWEEP_CONFIG = {
    "method": "random",
    "metric": {"name": "val/loss", "goal": "minimize"},
    "parameters": {
        "lr": {"distribution": "log_uniform_values", "min": 1e-5, "max": 1e-2},
        "batch_size": {"values": [16, 32, 64]},
        "epochs": {"value": 5}
    }
}

def train():
    with wandb.init() as run:
        cfg = run.config
        for epoch in range(cfg.epochs):
            # 替换为真实训练逻辑
            val_loss = 1.0 / (epoch + 1) + (0.01 if cfg.batch_size == 64 else 0.02)
            run.log({"epoch": epoch, "val/loss": val_loss})

if __name__ == "__main__":
    sweep_id = wandb.sweep(SWEEP_CONFIG, project="my-sweep")
    wandb.agent(sweep_id, function=train, count=10)
```

### 3.7 与 `wandb.config` 联动（来自同目录补充）

除 Sweeps 外，也可在 run 内动态更新配置：

```python
with wandb.init(project="config-demo") as run:
    run.config.update({
        "epochs": 100,
        "optimizer": "adam",
        "model": {"type": "transformer", "layers": 6}
    })
```

这个模式适合：

- 先手动实验，再过渡到 sweep 自动搜索。
- 在同一套日志系统里统一记录实验配置。

---

## 4. uv 全量能力索引（其余文件）

### 4.1 `docs/uv/02-projects.md`：项目元数据与依赖字段

主要功能：

- 在 `[project]` 定义 `name/version/description/readme/dependencies`。
- 支持 extras、环境标记。
- 可通过 `uv add` / `uv remove` 或手工编辑维护依赖。

示例：

```toml
[project]
name = "hello-world"
version = "0.1.0"
description = "Add your description here"
readme = "README.md"
dependencies = []
```

```toml
[project]
name = "albatross"
version = "0.1.0"
dependencies = [
  "tqdm >=4.66.2,<5",
  "torch ==2.2.2",
  "transformers[torch] >=4.39.3,<5",
  "importlib_metadata >=7.1.0,<8; python_version < '3.10'"
]
```

### 4.2 `docs/uv/03-commands.md`：锁文件同步

主要功能：

- 用 `uv pip sync` 将环境精确对齐到锁文件。
- 支持 `requirements.txt` 与 `pylock.toml`。

示例：

```bash
uv pip sync requirements.txt
uv pip sync pylock.toml
uv pip sync [OPTIONS] <SRC_FILE>...
```

### 4.3 `docs/uv/04-environments.md`：虚拟环境与 Python 版本

主要功能：

- 创建默认 `.venv` 或自定义名字。
- 指定 Python 版本并按需安装。

示例：

```bash
uv venv
uv venv my-name
uv venv --python 3.11.6
```

### 4.4 `docs/uv/05-workspaces-tools.md`：workspace 与命令执行

主要功能：

- `uv run` 在项目环境中执行 Python、CLI、脚本。
- workspace 根定义 `tool.uv.workspace`。
- 成员互相依赖通过 `tool.uv.sources` 的 `workspace = true`。

示例：

```bash
uv run python -c "import example"
uv run example-cli foo
uv run bash scripts/foo.sh
```

```toml
[tool.uv.sources]
bird-feeder = { workspace = true }

[tool.uv.workspace]
members = ["packages/*"]
exclude = ["packages/seeds"]
```

legacy 脚本运行示例：

```bash
uv tool run --from nuitka==2.6.7 nuitka --version
```

### 4.5 `docs/uv/06-configuration.md`：配置文件、缓存、索引

主要功能：

- `--config-file` 或 `UV_CONFIG_FILE` 指定 `uv.toml`。
- `cache-keys` 引入环境变量变化。
- `UV_INDEX` 注入自定义源。

示例：

```bash
uv --config-file /etc/uv/uv.toml
UV_CONFIG_FILE=/path/to/uv.toml uv lock
```

```toml
[tool.uv]
cache-keys = [{ file = "pyproject.toml" }, { env = "MY_ENV_VAR" }]
```

```bash
UV_INDEX=pytorch=https://download.pytorch.org/whl/cpu uv lock
```

### 4.6 `docs/uv/07-docker-cicd.md`：Docker、GitLab、Lambda

主要功能：

- 多阶段构建优化层缓存。
- `uv export` + `uv pip install --target` 适配 Lambda 镜像部署。
- GitLab CI 使用官方 uv 镜像与 `UV_LINK_MODE=copy`。

典型片段：

```Dockerfile
RUN --mount=type=cache,target=/root/.cache/uv \
    --mount=type=bind,source=uv.lock,target=uv.lock \
    --mount=type=bind,source=pyproject.toml,target=pyproject.toml \
    uv sync --locked --no-install-project
```

```yaml
variables:
  UV_VERSION: "0.10.2"
  PYTHON_VERSION: "3.12"
  BASE_LAYER: bookworm-slim
  UV_LINK_MODE: copy
```

---

## 5. wandb 全量能力索引（其余文件）

### 5.1 `docs/wandb/01-overview.md`：初始化总览

主要功能：

- `wandb.init()` 启动 run。
- context manager 自动 finish。
- 支持 Python 与 C# 示例。

Python 示例：

```python
with wandb.init(project="my-project", config={"lr": 0.001}) as run:
    run.log({"loss": 0.1, "accuracy": 0.9})
```

### 5.2 `docs/wandb/02-logging-tracking.md`：指标记录

主要功能：

- 训练中调用 `wandb.log({...})`。
- 记录 loss/accuracy/epoch 等。

示例：

```python
wandb.log({"accuracy": 0.95, "loss": 0.1})
```

### 5.3 `docs/wandb/03-artifacts.md`：版本化与下载

主要功能：

- 通过 `wandb.Artifact` 记录模型/数据。
- 通过 Public API 获取特定版本与版本列表。

示例：

```python
artifact = wandb.Artifact('my-model', type='model')
artifact.add_file('path/to/model.h5')
wandb.log_artifact(artifact)
```

### 5.4 `docs/wandb/05-reports-viz.md`：表格与可视化数据结构

主要功能：

- 记录 `wandb.Table` 用于分析。
- 文档中附带 lipgloss 终端渲染示例（Go）。

示例：

```python
run.log({"table1": wandb.Table(columns=["id", "score"], data=[[1, 0.9], [2, 0.8]])})
```

### 5.5 `docs/wandb/06-integrations.md`：框架集成

主要功能：

- Keras：`WandbMetricsLogger`, `WandbModelCheckpoint`。
- PyTorch Lightning：`WandbLogger`。
- XGBoost：`WandbCallback`。
- Artifacts + Registry 联动。

示例：

```python
from wandb.integration.keras import WandbMetricsLogger, WandbModelCheckpoint
from pytorch_lightning.loggers import WandbLogger
from wandb.integration.xgboost import WandbCallback
```

### 5.6 `docs/wandb/07-api-config.md`：登录与 API key

主要功能：

- 登录、初始化 run。
- API key 的配置入口与安全存储提醒。

示例：

```python
wandb.login(relogin=True, timeout=5)
wandb.init(project="my-project", entity="my-entity")
```

### 5.7 `docs/wandb/08-alerts-registry.md`：告警与注册表

主要功能：

- 在运行中调用 `run.alert(...)` 发送通知。
- 继续复用 artifacts 模式并关联 registry。

示例：

```python
run.alert(
    title="High Accuracy Achieved!",
    text="Model reached target",
    level=wandb.AlertLevel.INFO
)
```

---

## 6. 直接复用模板（优先给用户）

### 6.1 uv + wandb 最小闭环

```bash
# 1) 安装 uv（任选其一）
curl -LsSf https://astral.sh/uv/install.sh | sh
# 或 winget install --id=astral-sh.uv -e
# 或 pipx install uv

# 2) 创建环境并安装依赖
uv venv --python 3.12
uv pip sync requirements.txt

# 3) 运行训练脚本
uv run python train.py
```

```python
# train.py
import wandb

with wandb.init(project="demo", config={"lr": 3e-4, "epochs": 3}) as run:
    for epoch in range(run.config.epochs):
        loss = 1.0 / (epoch + 1)
        run.log({"epoch": epoch, "loss": loss})
```

### 6.2 直接可跑的 Sweep 模板

```python
import wandb

sweep_config = {
    "method": "bayes",
    "metric": {"name": "val/accuracy", "goal": "maximize"},
    "parameters": {
        "learning_rate": {"distribution": "log_uniform_values", "min": 1e-5, "max": 1e-2},
        "batch_size": {"values": [16, 32, 64]},
        "epochs": {"value": 5}
    },
    "early_terminate": {"type": "hyperband", "min_iter": 2}
}


def train():
    with wandb.init() as run:
        cfg = run.config
        for epoch in range(cfg.epochs):
            acc = 0.70 + epoch * 0.02
            run.log({"epoch": epoch, "val/accuracy": acc})


if __name__ == "__main__":
    sid = wandb.sweep(sweep_config, project="sweep-demo")
    wandb.agent(sid, function=train, count=8)
```

---

## 7. 问答路由规则（给执行代理）

当用户提问时，按以下规则路由：

1. 包含 “安装 uv / 怎么装 uv / uv installer / winget / pipx”
- 走 `docs/uv/01-overview.md`。
- 先给三种安装方式，再给 PATH 与验证。

2. 包含 “sweep / 超参数 / bayes / grid / random / wandb 调参”
- 走 `docs/wandb/04-sweeps.md`。
- 必给完整 `sweep_config + train + agent`。

3. 包含 “依赖锁定 / requirements 对齐 / pylock”
- 走 `docs/uv/03-commands.md`。

4. 包含 “workspace / monorepo / 多包”
- 走 `docs/uv/05-workspaces-tools.md`。

5. 包含 “artifact / 模型版本 / 数据集版本 / registry”
- 走 `docs/wandb/03-artifacts.md` + `docs/wandb/08-alerts-registry.md`。

6. 包含 “Keras / Lightning / XGBoost”
- 走 `docs/wandb/06-integrations.md`。

7. 包含 “登录失败 / api key”
- 走 `docs/wandb/07-api-config.md`。

---

## 8. 高价值排错清单

### 8.1 uv 侧

1. 命令不存在
- 检查 PATH。
- 容器中确认 `/root/.local/bin`。

2. 依赖不同步
- 确认使用 `uv pip sync` 而非普通安装。
- 重新检查 lock 文件是否最新。

3. workspace 源不生效
- 检查 `tool.uv.sources` 是否 `workspace = true`。
- 检查成员目录是否存在 `pyproject.toml`。

4. Docker 缓存效果差
- 把依赖安装层放在复制项目代码之前。
- 使用 `--mount=type=cache,target=/root/.cache/uv`。

### 8.2 wandb 侧

1. 看不到日志
- 确认 run 已初始化。
- 确认 `wandb.log` 在训练循环中被调用。

2. Sweeps 不优化目标
- `metric.name` 与 `run.log` 字段名不一致。
- `metric.goal` 配反。

3. Sweeps 参数不生效
- 没有从 `run.config` 读取参数。

4. Artifacts 无法追踪
- 忘记 `run.log_artifact(...)`。
- 别名策略不清晰（`latest`、`best`、`production`）。

5. 告警未触发
- 未调用 `run.alert`。
- 条件分支从未命中。

---

## 9. 输出模板（建议直接复用）

### 模板 A：安装型问题

1. 给 1 条最短命令。
2. 给 2 条替代方案（Windows / pipx）。
3. 给 3 条验证与排错。
4. 标注来源：`docs/uv/01-overview.md`。

### 模板 B：Sweep 型问题

1. 先解释 `method + metric + parameters`。
2. 贴 `sweep_config`。
3. 贴 `train()`（必须 `with wandb.init()`）。
4. 贴 `wandb.agent(..., count=...)`。
5. 标注来源：`docs/wandb/04-sweeps.md`。

### 模板 C：工程落地型问题（uv + wandb）

1. 依赖与环境：`uv venv` + `uv pip sync`。
2. 训练日志：`wandb.init` + `run.log`。
3. 产物版本：`wandb.Artifact`。
4. 调参：Sweeps。
5. 部署：Docker/CI 分层缓存。

---

## 10. 术语与键名对照

- `uv pip sync`：将环境严格对齐 lock/requirements。
- `uv venv --python X.Y`：按 Python 版本建虚拟环境。
- `tool.uv.workspace`：workspace 成员集合定义。
- `tool.uv.sources`：依赖来源覆盖（含 workspace source）。
- `wandb.init`：创建实验运行。
- `run.log` / `wandb.log`：记录指标。
- `wandb.Artifact`：版本化数据与模型。
- `wandb.sweep`：创建 sweep。
- `wandb.agent`：执行 sweep 任务。
- `run.config`：运行配置与超参数读取入口。
- `run.alert`：运行内告警通知。

---

## 11. 最终要求（执行约束）

- 遇到超参问题，默认给 Sweeps 模板，不只讲概念。
- 遇到安装问题，默认给三平台方案（Linux/macOS、Windows、pipx）。
- 遇到部署问题，默认补充 Docker 缓存层优化。
- 对于本技能中的重点主题，优先引用：
  - `docs/uv/01-overview.md`
  - `docs/wandb/04-sweeps.md`

