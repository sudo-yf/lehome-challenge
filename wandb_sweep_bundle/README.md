# wandb-sweep-bundle

这是一套可以一起拷走的 LeHome W&B Sweep 运行包，面向“下一台机器快速无脑跑通”。

## 包含内容

- `justfile`：统一命令入口
- `bin/`：对外 shell 命令
- `lib/`：公共环境与路径解析
- `scripts/`：W&B sweep / preflight / reproducibility Python 逻辑
- `configs/`：XVLA 相关训练与 sweep YAML
- `env.example`：最小环境变量模板

## 适用前提

目标机器需要已经具备：
- LeHome 仓库工作区（包含 `pyproject.toml`）
- `.venv`
- 数据集目录，例如 `Datasets/example/top_long_merged`
- 可用的 W&B API key 文件

## 最小准备

1. 复制整个 `wandb_sweep_bundle/` 目录到目标机器
2. 设置环境变量：

```bash
export LEHOME_WORKSPACE_ROOT=/path/to/lehome-challenge
export WANDB_ENV_FILE=/path/to/wandb.md
```

3. 可选地加载 `env.example` 中的缓存目录设置

## 推荐运行顺序（工程稳态版）

### 1. 预检

```bash
just -f wandb_sweep_bundle/justfile preflight
```

### 2. dry-run

```bash
just -f wandb_sweep_bundle/justfile dryrun steps=100
```

### 3. 首次在线 100 步 smoke

如果目标机器还没有 HF/XVLA 缓存，先在线跑一次：

```bash
just -f wandb_sweep_bundle/justfile smoke100-online
```

### 4. 后续离线 100 步 smoke

```bash
just -f wandb_sweep_bundle/justfile smoke100-offline
```

### 5. 连续 3 次 100 步验证 agent

```bash
just -f wandb_sweep_bundle/justfile smoke3x100-offline
```

### 6. 创建正式 sweep

```bash
just -f wandb_sweep_bundle/justfile create-only steps=3000 count=8
```

### 7. 接回已有 sweep

```bash
just -f wandb_sweep_bundle/justfile attach <sweep_id> count=4
```

## 高级：正式可复现模式

严格模式会先冻结：
- code snapshot
- dataset manifest
- environment manifest
- sweep manifest

并在每个 agent run 启动前校验：
- git commit / dirty 状态
- dataset hash
- environment hash

### 严格模式创建 sweep

```bash
just -f wandb_sweep_bundle/justfile strict-create steps=100
```

### 严格模式接回 sweep

```bash
just -f wandb_sweep_bundle/justfile strict-attach <sweep_id> count=1
```

说明：
- 生产环境不建议使用 `--allow-dirty`
- 严格模式要求“创建 sweep”和“接回 sweep”使用同一套关键环境变量
- 当前实现把 W&B 数据与 artifact staging 指向数据盘，避免系统盘写爆

## 成功判据

- `preflight`：返回有效 W&B run URL
- `dryrun`：打印合法 sweep config
- `smoke100-*`：训练能跑到 `step=100`
- W&B Runs 表格可直接看到：
  - `config.batch_size`
  - `config.steps`
  - `config.log_freq`
  - `config.policy_optimizer_lr`
  - `config.policy_optimizer_weight_decay`
  - `config.policy_scheduler_warmup_steps`
- run 名称应自动带关键超参数，例如：
  - `xvla_bs4_s100_lr1.98e-05_wd1.00e-04_warm2000_log100`

## 常见问题

- **HF 首次加载很慢**：先用 `smoke100-online` 热缓存，之后用 offline 模式
- **W&B artifact staging 爆系统盘**：设置 `WANDB_DATA_DIR` / `WANDB_ARTIFACT_DIR` 到数据盘
- **strict 模式直接 fail**：通常说明 git / dataset / environment 与创建 sweep 时不一致
- **Runs 看不到超参数列**：在 W&B Runs 表中手动添加 `config.policy_optimizer_lr` 等列
