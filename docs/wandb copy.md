> 注意：不要把真实 `W&B API Key` 明文写进文档、仓库、截图或日志。示例统一使用 `<your_api_key>`。

>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
# WandB 基础设置与自动化调参手册

这份文档只抓两件事：
- 把 `wandb` 的基础设置配顺。
- 把 `Sweeps` 自动化调参讲明白，直接能跑。

别把重点搞歪。
`uv` 只是可选执行器，不是主角。

本稿优先参考这些本地文件：
- `docs/wandb/02-logging-tracking.md`
- `docs/wandb/04-sweeps.md`
- `docs/wandb/07-api-config.md`
- `docs/wandb/01-overview.md`（只取 `wandb.init` 的实用部分）

---

## 1. 怎么回答这类问题

默认顺序：
1. 先给最小可运行命令或代码。
2. 再解释关键参数。
3. 再给常见报错和修法。
4. 最后标注来源文件。

路由规则：
- 问 `wandb 怎么装 / 怎么登录 / api key`：先讲基础设置。
- 问 `loss 怎么记 / accuracy 怎么看 / config 怎么传`：先讲标准 run 模板。
- 问 `自动调参 / 超参数搜索 / bayes / random / grid / sweep`：直接切到 Sweeps。
- 问 `uv`：最后再补，别反客为主。

---

## 2. 基础设置

### 2.1 安装

```bash
pip install wandb -i https://pypi.tuna.tsinghua.edu.cn/simple
```

参数说明：
- `-i https://pypi.tuna.tsinghua.edu.cn/simple`：清华镜像，国内通常更稳。

适用场景：本机、服务器、开发环境首次安装 `wandb`。

### 2.2 登录

命令行登录：

```bash
wandb login
```

环境变量免密登录：

```bash
export WANDB_API_KEY=<your_api_key>
```

Python 内登录：

```python
import wandb

wandb.login(relogin=True, timeout=5)
```

参数说明：
- `WANDB_API_KEY`：适合本地长期使用和 CI 注入。
- `relogin=True`：强制重新认证。
- `timeout=5`：登录超时时间，单位秒。

关键点：
- API Key 只应该放环境变量、密码管理器或 CI Secret。
- 不要把真实 key 写进仓库、脚本、文档。

适用场景：本地开发、远程训练机、CI/CD。

### 2.3 最小可运行示例

```python
import wandb

project = "my-awesome-project"
config = {"epochs": 10, "lr": 3e-4}

with wandb.init(project=project, config=config) as run:
    run.log({"accuracy": 0.9, "loss": 0.1})
```

关键点：
- `with wandb.init(...) as run`：推荐写法；离开代码块会自动结束 run。
- 如果代码异常退出，`with` 写法也比手动收尾稳。
- `run.log(...)`：记录训练过程指标。

适用场景：第一次接入 WandB，先验证链路通不通。

### 2.4 推荐的标准 run 模板

这段比“最小示例”更适合真实项目。

```python
import wandb

with wandb.init(
    project="my-project",
    entity="my-team",
    name="experiment-1",
    config={
        "learning_rate": 0.001,
        "epochs": 10,
        "batch_size": 32,
        "architecture": "resnet50",
    },
    tags=["baseline", "v1"],
    notes="First baseline experiment"
) as run:
    for epoch in range(10):
        run.log({
            "epoch": epoch,
            "loss": 0.5 - epoch * 0.04,
            "accuracy": 0.7 + epoch * 0.02,
        })
```

参数说明：
- `project`：项目名。别今天一个、明天一个。
- `entity`：团队或账号实体。
- `name`：当前实验名，建议可读、可检索。
- `config`：超参数、模型结构、训练设置。
- `tags`：标签，方便筛选。
- `notes`：备注，适合写这次实验的意图。

适用场景：日常训练、基线实验、模型对比。

### 2.5 手动模式、离线模式、恢复运行

如果不想用 `with`，可以手动控制：

```python
import wandb

run = wandb.init(
    project="my-project",
    config={"lr": 0.01},
    mode="online",   # "online", "offline", or "disabled"
    resume="allow",  # 如果存在则恢复
    id="unique-run-id"
)

run.log({"loss": 0.1})
run.finish()
```

参数说明：
- `mode="online"`：在线同步。
- `mode="offline"`：先本地记录，之后再同步。
- `mode="disabled"`：禁用 WandB 上报。
- `resume="allow"`：若 run 存在则恢复，否则新建。
- `id`：自定义 run ID，用于恢复或串联任务。

适用场景：Notebook、断点续跑、临时关闭联网同步。

### 2.6 配置管理：`run.config` / `wandb.config`

`config` 不只是初始化时塞几个参数。
它本身就是实验配置中心。

```python
import wandb

with wandb.init(project="config-demo") as run:
    run.config.learning_rate = 0.001
    run.config.batch_size = 32

    run.config.update({
        "epochs": 100,
        "optimizer": "adam",
        "model": {
            "type": "transformer",
            "layers": 6,
            "hidden_size": 512,
        }
    })

    lr = run.config.learning_rate
    print(lr)
    print(wandb.config.batch_size)
```

关键点：
- `run.config`：推荐入口。
- `wandb.config`：全局访问入口。
- 初始化时传一部分，运行中继续 `update()` 也行。

适用场景：实验配置复杂、需要动态补充配置的时候。

### 2.7 基础设置默认建议

用户没特别说明时，默认这么给：
- 用 `with wandb.init(...) as run`。
- `project`、`name`、`config` 必填。
- 有团队空间就补 `entity`。
- 训练过程统一用 `run.log(...)`。
- 需要长期管理时补 `tags`、`notes`。
- 跑在不稳定网络或离线机器上时，考虑 `mode="offline"`。

适用场景：用户只说“帮我把 WandB 基础配置好”。

---

## 3. 基础排错

### 3.1 登录类问题

#### `wandb: command not found`
- 原因：包没装对，或者当前环境不对。
- 修法：先确认安装，再确认你进的是正确 Python 环境。

#### 每次都要重新登录
- 原因：没有持久化认证。
- 修法：设置 `WANDB_API_KEY`。

#### 远程机器登录麻烦
- 修法：优先用环境变量，不要在服务器上反复交互。

### 3.2 记录类问题

#### 页面里看不到指标
- 原因：没成功 `wandb.init()`，或者根本没执行到 `run.log()`。
- 修法：先跑最小示例，确认链路通，再接训练逻辑。

#### 指标名乱七八糟
- 原因：日志 key 没规范。
- 修法：统一命名，例如 `train/loss`、`val/loss`、`val/accuracy`。

#### 配置没记全
- 原因：只记 loss，不记超参数。
- 修法：学习率、batch size、epochs、optimizer、model 都放进 `config`。

适用场景：WandB 已经接上，但结果很乱、难查、难复现。

---

## 4. 自动化调参：Sweeps

这一节是重点。
只要用户问调参，默认给这套。

### 4.1 最小工作流

1. 定义 `sweep_config`。
2. 设定搜索策略 `method`。
3. 指定目标指标 `metric.name` 和优化方向 `metric.goal`。
4. 定义搜索空间 `parameters`。
5. 编写 `train()`，内部用 `with wandb.init()`。
6. 从 `run.config` 读取参数。
7. 用 `run.log()` 上报目标指标。
8. 调用 `wandb.agent(...)` 执行多次实验。

### 4.2 推荐的 Sweeps 模板

这段直接能跑。
而且和本地 `docs/wandb/04-sweeps.md` 基本一致。

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

适用场景：第一次上 Sweep，或要给用户一个标准答案。

### 4.3 `sweep_config` 必须讲清楚的字段

#### `method`
可选：
- `grid`
- `random`
- `bayes`

怎么选：
- 参数空间小、而且全是离散值：用 `grid`。
- 想先快速扫一遍：用 `random`。
- 预算有限，想更聪明地搜：用 `bayes`。

#### `metric.name`
- 指定优化目标的日志字段名。
- 必须和 `run.log()` 里的键完全一致。

比如：
```python
run.log({"val/accuracy": accuracy})
```
那 `metric.name` 就必须是 `val/accuracy`。

#### `metric.goal`
- `maximize`：越大越好，比如准确率。
- `minimize`：越小越好，比如 loss。

#### `parameters`
支持三类常见写法：
- `value`：固定值。
- `values`：离散候选值。
- `distribution + min/max`：连续范围采样。

#### `early_terminate`
- 常见是 `hyperband`。
- `min_iter` 用来限制早停触发时机。
- 作用就是：烂配置早点停，别浪费卡。

#### `count`
- Agent 运行次数上限。
- 这个不写清楚，预算很容易失控。

### 4.4 Sweep 训练函数的硬规则

这几条必须守：
- `train()` 里重新 `wandb.init()`。
- 所有超参数从 `run.config` 读取。
- `metric.name` 和 `run.log()` 键名完全一致。
- 目标指标要持续记录，不要只打一轮。
- `count` 要明确，不要让 agent 无限跑。

适用场景：写 Sweep 训练函数时自检。

### 4.5 第一次做自动调参时的默认策略

如果用户没给太多背景，默认这么给：
- `method="random"` 或 `method="bayes"`
- 搜 `learning_rate`
- 搜 `batch_size`
- 搜 `optimizer`
- 固定 `epochs`
- 开 `early_terminate.hyperband`
- `count=10` 或 `20`

这不一定最猛。
但够稳，够省事，够像人干的事。

适用场景：用户只说“帮我做自动调参”。

### 4.6 Sweeps 常见翻车点

#### 没有优化到目标指标
- 原因：`metric.name` 和 `run.log()` 键名不一致。
- 修法：目标字段名一模一样，别写成两个版本。

#### 参数根本没变
- 原因：你没从 `run.config` 读，而是把学习率写死了。
- 修法：所有待搜索参数都从 `config = run.config` 取。

#### 跑太多，预算爆炸
- 原因：没设 `count`，或者多 agent 并发没规划。
- 修法：先定预算，再定 `count`。

#### 训练代码报错但 Sweep 还在跑
- 原因：没做异常处理，失败 run 也没留下有效信息。
- 修法：在训练逻辑里加异常捕获，并记录上下文。

适用场景：Sweep 能启动，但结果不稳定、不可信。

---

## 5. 直接给用户的回复模板

### 5.1 用户问基础设置

输出顺序：
1. 安装命令。
2. `wandb login`。
3. `WANDB_API_KEY` 免密方案。
4. 一个最小 `wandb.init + run.log` 示例。
5. 两三条常见报错。

优先来源：
- `docs/wandb/02-logging-tracking.md`
- `docs/wandb/07-api-config.md`
- `docs/wandb/01-overview.md`

### 5.2 用户问自动调参

输出顺序：
1. 解释 `method`、`metric`、`parameters`。
2. 贴完整 `sweep_config`。
3. 贴 `train()`，并使用 `with wandb.init()`。
4. 贴 `wandb.agent(..., count=...)`。
5. 强调 `metric.name` 和日志键一致。

优先来源：
- `docs/wandb/04-sweeps.md`

### 5.3 用户问工程化落地

输出顺序：
1. 用标准 run 模板。
2. 把 `project / entity / name / config / tags / notes` 统一起来。
3. 训练中只用 `run.log()` 记过程指标。
4. 如果要调参，再接 Sweeps。

优先来源：
- `docs/wandb/01-overview.md`
- `docs/wandb/02-logging-tracking.md`
- `docs/wandb/04-sweeps.md`

---

## 6. 附录：`uv` 只保留最小必要内容

项目已经在用 `uv` 时，给这三条就够了：

```bash
uv venv --python 3.12
uv pip install wandb
uv run python train.py
```

适用场景：项目已经用 `uv` 管 Python 环境。

---

## 7. 最终执行约束

- 遇到 `wandb` 问题，先讲基础设置，再讲扩展功能。
- 遇到自动调参问题，默认给 `Sweeps` 完整模板，不要只讲概念。
- 优先统一 `project / entity / name / config / tags / notes` 这一套基本盘。
- `uv` 只在用户明确需要时再展开。
- 真正优先看的本地文件是：
  - `docs/wandb/02-logging-tracking.md`
  - `docs/wandb/04-sweeps.md`
  - `docs/wandb/07-api-config.md`
  - `docs/wandb/01-overview.md`
