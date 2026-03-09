# LeHome Challenge

LeHome Challenge 是一个围绕家庭场景服装操作任务构建的训练与评估仓库，当前主力工作流基于：
- `LeHome`
- `IsaacLab`
- `LeRobot`
- `WandB`（可选，用于实验跟踪与 sweep）

这个仓库现在已经把**日常使用入口**统一收敛到 `lehome/` 目录下，但**真实训练与评估逻辑**仍然保留在仓库根目录脚本中：
- `run_train.sh`
- `run_eval.sh`

如果你是第一次接手这个项目，推荐先看这份 README；如果你要了解入口脚本的细节，再看 `lehome/README.md`。

## 快速开始

### 1. 环境准备

在仓库根目录执行：

```bash
just prepare --install-system-libs
just data --with-full-dataset
```

如果想一次跑完完整准备流程：

```bash
just setup --install-system-libs --with-full-dataset
```

### 2. 训练与评估

常规训练 / 评估示例：

```bash
just train act 1000
just eval act
```

也支持其他模型，例如：

```bash
just train diffusion
just train smolvla
just train xvla
```

### 3. XVLA / WandB 相关

```bash
just xvla
just wandb
just sweep --preflight --model xvla
just sweep --dry-run --model xvla --steps 1000
```

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
| `just save <版本号>` | `bash lehome/allinone.sh save <版本号>` | 备份 / 打版本 |

## 目录说明

- `lehome/`：当前主力入口目录
- `lehome/v1/`：旧版 `start/step*.sh` 备份
- `configs/`：训练配置
- `docs/`：补充文档
- `scripts/`：辅助脚本（包括 WandB sweep Python 入口）
- `run_train.sh`：真实训练入口
- `run_eval.sh`：真实评估入口

## 什么时候看 `lehome/README.md`

大多数情况下，直接在仓库根目录用 `just` 就够了。

只有在下面场景，建议再看 `lehome/README.md`：
- 你想了解新入口脚本的组织方式
- 你想直接运行 `allinone.sh`、`xvla.sh`、`wandb.sh`、`sweep.sh`
- 你想区分“入口层”和“真实执行层”的职责

## 文档索引

- `lehome/README.md`：主入口脚本的详细操作手册
- `lehome/v1/README.md`：旧版脚本备份说明
- `docs/training.md`：训练说明
- `docs/policy_eval.md`：评估说明
- `docs/wandb.md`：WandB 说明

## 说明

- 旧版脚本没有删除，而是归档到了 `lehome/v1/`
- 新入口层主要负责**命令分发、展示、预检和可视化体验**
- 真实训练与评估逻辑仍由仓库根目录脚本负责，因此入口目录调整不会改变核心执行行为
