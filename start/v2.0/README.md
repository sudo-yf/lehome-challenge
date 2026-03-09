# LeHome Challenge Workflow v2

`v2/` 保留原仓库不动，把主流程收敛成 `step1 / step2 / step3` 三步。

## 推荐顺序

1. `bash v2/vpn.sh`（可选，网络不稳时再开）
2. `bash v2/step1.sh [--install-system-libs]`
3. `bash v2/step2.sh`
4. `bash v2/step3.sh [--with-full-dataset]`
5. `bash v2/train.sh ...`
6. `bash v2/eval.sh ...`
7. `bash v2/save.sh <version>`

也可以直接一条命令跑主流程：

```bash
bash v2/setup.sh --install-system-libs --with-full-dataset
```

## 三步职责

- `step1.sh`：安装前准备 + `uv sync` + IsaacLab + LeHome + `hf` + 核心导入校验（训练默认输出目录若已存在会自动顺延到 `_2/_3/...`）
- `step2.sh`：IsaacSim EULA、`_isaac_sim` 软链接、轻量 shell 快捷命令
- `step3.sh`：Assets、合并数据集、可选完整 `dataset_challenge`

## 工具脚本

- `vpn.sh`：代理/加速，可选
- `train.sh`：训练入口
- `eval.sh`：评估入口
- `save.sh`：备份/打版本

## `just` 用法

进入 `v2/` 后可以直接使用：

```bash
cd v2
just step1 --install-system-libs
just step2
just step3 --with-full-dataset
just train act 1000
just eval act
just save 1
```
