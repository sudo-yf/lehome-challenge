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
