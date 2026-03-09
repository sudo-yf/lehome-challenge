# LeHome 主入口手册

`lehome/` 是当前项目的主力脚本目录。

设计目标：
- 让常用入口尽量少
- 把“环境准备 / 数据下载 / 训练 / 评估 / XVLA / WandB / 版本管理”收进统一结构
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
- `versioning.sh`：版本保存 / 索引逻辑
- `common.sh`：公共辅助函数
- `justfile`：目录内快捷命令

历史备份：
- `v1/`：原始 `start/step*.sh` 备份，不再作为主入口

## 最常用命令

```bash
cd lehome
just prepare --install-system-libs
just data --with-full-dataset
just train act 1000
just eval act
just xvla
just wandb
just sweep --dry-run --model xvla --steps 1000
just save 3 xvla wandb
just versions
```

## 版本管理

### `save`

`save` 现在支持：
- 版本号
- 备注
- 默认不覆盖已有 tag
- 自动刷新 `VERSIONS.md`

示例：

```bash
just save 3 xvla wandb sweep
bash allinone.sh save 3 --note "xvla wandb sweep"
bash allinone.sh save v3 --local-only
bash allinone.sh save v3 --force-tag --note "overwrite tag intentionally"
```

默认行为：
- 如果工作区有改动，会先提交
- 如果工作区没有改动，会创建一个空提交作为版本锚点
- 然后创建 annotated tag
- 最后刷新 `VERSIONS.md`

### `versions`

`versions` 会根据当前 Git tag 重新生成并展示 `VERSIONS.md`。

示例：

```bash
just versions
bash allinone.sh versions
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
- `versions`

### `prepare.sh`

负责环境准备，包含：
- `uv sync`
- IsaacLab / LeHome / HuggingFace CLI 安装
- 核心导入校验
- IsaacSim EULA 授权
- `_isaac_sim` 软链接
- shell 快捷命令写入

### `data.sh`

负责数据资源下载，包含：
- `Assets`
- 合并版示例数据集
- 可选完整 `dataset_challenge`

### `train.sh` / `eval.sh`

这两个就是当前正式的训练 / 评估入口脚本。

### `xvla.sh`

XVLA 专用入口，支持：
- `WORK_MODE=install`
- `WORK_MODE=train`
- `WORK_MODE=eval`

### `wandb.sh`

只做 WandB 预检，不直接启动训练。

### `sweep.sh`

负责 WandB sweep 自动调参入口，底层调用：
- `scripts/wandb_sweep.py`
