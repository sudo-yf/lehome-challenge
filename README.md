# LeHome Challenge

LeHome Challenge 是一个围绕家庭场景服装操作任务构建的训练与评估仓库，当前主力工作流基于：
- `LeHome`
- `IsaacLab`
- `LeRobot`
- `WandB`（可选，用于实验跟踪与 sweep）

当前项目的主力入口目录是 `lehome/`，而旧版脚本已经归档到 `lehome/v1/`。

## 快速开始

### 环境准备

```bash
just prepare --install-system-libs
just data --with-full-dataset
```

一次性跑完整准备流程：

```bash
just setup --install-system-libs --with-full-dataset
```

### 常规训练 / 评估

```bash
just train act 1000
just eval act
```

### XVLA / WandB / Sweep

```bash
just xvla
just wandb
just sweep --dry-run --model xvla --steps 1000
```

### 保存和查版本

```bash
just save 3 xvla wandb sweep
just versions
```

说明：
- `just save` 现在支持备注，备注会进入版本索引
- 默认不会覆盖已有 tag；如需强制覆盖，要显式传 `--force-tag`
- `VERSIONS.md` 会自动维护版本、日期、commit、备注索引

## 根目录 `just` 命令

| 命令 | 实际执行 | 作用 |
| --- | --- | --- |
| `just vpn` | `bash lehome/allinone.sh vpn` | 代理 / 加速入口 |
| `just prepare` | `bash lehome/allinone.sh prepare ...` | 环境准备 |
| `just data` | `bash lehome/allinone.sh data ...` | 数据下载 |
| `just setup` | `bash lehome/allinone.sh setup ...` | 一次性执行 `prepare + data` |
| `just train` | `bash lehome/train.sh ...` | 通用训练入口 |
| `just eval` | `bash lehome/eval.sh ...` | 通用评估入口 |
| `just xvla` | `bash lehome/xvla.sh ...` | XVLA 专用入口 |
| `just wandb` | `bash lehome/wandb.sh ...` | WandB 预检 |
| `just sweep` | `bash lehome/sweep.sh ...` | WandB sweep |
| `just save ...` | `bash lehome/allinone.sh save ...` | 保存版本，支持备注 |
| `just versions` | `bash lehome/allinone.sh versions` | 列出并刷新版本索引 |

## 目录说明

- `lehome/`：当前主力入口目录
- `lehome/v1/`：旧版 `start/step*.sh` 备份
- `VERSIONS.md`：版本索引
- `configs/`：训练配置
- `docs/`：补充文档
- `scripts/`：辅助脚本（包括 WandB sweep Python 入口）

## 文档索引

- `lehome/README.md`：主入口脚本操作手册
- `lehome/v1/README.md`：旧版脚本备份说明
- `docs/training.md`：训练说明
- `docs/policy_eval.md`：评估说明
- `docs/wandb.md`：WandB 说明
