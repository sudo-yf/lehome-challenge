# LeHome Challenge `just` 命令说明

本文档说明 `justfile` 里的核心命令，以及它们实际会执行的脚本行为。

## 先决条件

- 已安装 `just`（可通过 `just --list` 查看命令）
- 在仓库根目录 `/root/data/lehome-challenge` 下执行
- 建议使用可写 `~/.bashrc`、可执行 `apt/git/hf/uv` 的环境

## 命令总览

| 命令 | 实际执行 | 作用 |
| --- | --- | --- |
| `just vpn` | `bash start/step_vpn.sh` | 安装并配置 Clash for Linux 代理环境 |
| `just s1` | `bash start/step1.sh` | 基础环境安装（`uv`、依赖、IsaacLab、LeHome 包、基础数据） |
| `just s2` | `bash start/step2.sh` | 按官方步骤补全安装与数据下载 |
| `just s3` | `bash start/step3.sh` | Shell 快捷命令、IsaacSim 授权、IsaacLab 路径软链接 |
| `just save <版本号>` | `bash start/step_git.sh <版本号>` | 自动提交并打 Tag 推送到 GitHub |
| `just train [model]` | `bash run_train.sh [model]` | 启动训练并记录日志 |
| `just eval [model] [policy_path] [garment] [episodes] [dataset_root]` | `bash run_eval.sh ...` | 启动评估并记录日志 |

## 1) `just vpn`

执行脚本：`start/step_vpn.sh`

会做的事情：

1. 尝试启用 `/public/bin/network_accelerate`（如果存在）。
2. 重新克隆 `nelvko/clash-for-linux-install`。
3. 修改安装脚本，去掉 `gh-proxy` 前缀。
4. 写入 `.env`（包含内核版本、订阅地址、控制面板地址等）。
5. 执行 `install.sh` 完成安装。
6. 尝试关闭加速脚本 `/public/bin/network_accelerate_stop`（如果存在）。

适用场景：网络需要代理加速，或你要重装 Clash 代理环境。

## 2) `just s1`

执行脚本：`start/step1.sh`

会做的事情：

1. 可选安装系统图形依赖（脚本会交互询问，`y/N`）。
2. 检查并安装 `uv`。
3. 若当前不在仓库目录，会克隆 `lehome-official/lehome-challenge`。
4. 执行 `uv sync` 安装 Python 依赖。
5. 克隆 `third_party/IsaacLab`（如果不存在）。
6. 在虚拟环境中执行：
   - `./third_party/IsaacLab/isaaclab.sh -i none`
   - `uv pip install -e ./source/lehome`
   - `uv pip install "huggingface_hub[cli]"`
7. 下载：
   - `lehome/asset_challenge` 到 `Assets`
   - `lehome/dataset_challenge_merged` 到 `Datasets/example`

适用场景：第一次完整初始化环境。

## 3) `just s2`

执行脚本：`start/step2.sh`

会做的事情（偏官方文档复刻）：

1. 自动定位到 `lehome-challenge` 目录。
2. `source .venv/bin/activate` 激活虚拟环境。
3. 再次执行 `./third_party/IsaacLab/isaaclab.sh -i none`。
4. 再次执行 `uv pip install -e ./source/lehome`。
5. 下载数据：
   - `asset_challenge`
   - `dataset_challenge_merged`
   - `dataset_challenge`（包含 depth 信息）

适用场景：在 `s1` 后补齐官方下载项，或重跑下载步骤。

## 4) `just s3`

执行脚本：`start/step3.sh`

会做的事情：

1. 建立缓存软链接：`~/.cache/uv -> /root/data/.uv_cache`。
2. 修改 `~/.bashrc`，加入：
   - `PATH` 补充
   - `cd` 自动激活 `.venv` 的函数别名
   - `go` 快捷命令（进入项目并激活环境）
   - `save` 快捷命令（当前写入的是 `bash /root/data/lehome-challenge/start/step_git.sh`）
3. 激活 `.venv` 后触发 `python -c "import isaacsim"`，用于 EULA 授权。
4. 获取 `isaacsim` 安装路径并创建软链接：
   `third_party/IsaacLab/_isaac_sim -> <isaacsim包路径>`。

适用场景：完成 shell 使用体验优化和 IsaacSim 路径联通。

## 5) `just save <版本号>`

执行脚本：`start/step_git.sh <版本号>`

会做的事情：

1. 校验版本号参数，生成 Tag（如 `v10`）。
2. 进入 `/root/data/lehome-challenge` 并尝试激活 `.venv`。
3. 检查 Git 身份，缺失时自动设置为脚本内默认值。
4. 若检测到 `origin` 指向官方仓库，会自动改为个人仓库地址并添加 `upstream`。
5. 执行 `git add .`、`git commit`（无变更则跳过）。
6. 重建同名 Tag 并推送当前分支和 Tag。

适用场景：你希望一条命令完成提交+打版本标签+推送。

## 6) `just train [model]`

执行脚本：`run_train.sh`

参数说明：

- `model`（可选，默认 `act`）：支持 `act` / `diffusion` / `smolvla`（兼容别名 `dp`）
- `steps`（可选）：支持多种写法  
  - `just train act 1000`  
  - `just train act step1000`  
  - `just train act step 1000`  
  - `just train act steps=1000`  
  - `just train act --steps 1000`
- 其余参数会原样透传给 `lerobot-train`

会做的事情：

1. 自动定位到脚本所在项目目录，不依赖固定的 `$HOME/data` 路径。
2. 激活 `.venv`（若不存在会报错退出）。
3. 根据 `model` 选择配置文件：`act -> train_act.yaml`，`diffusion -> train_dp.yaml`，`smolvla -> train_smolvla.yaml`。
4. 直接按配置文件执行 `lerobot-train`（不强制覆盖 `output_dir` / `wandb` / `device`），日志写入 `logs/` 目录。

注意：

- 若配置中的 `output_dir` 已存在，脚本会直接报错退出（避免覆盖）。
- 这时请改新目录（`--output_dir`）或使用 `--resume=true --config_path <旧目录>/train_config.json` 续训。

示例：

```bash
just train
just train act 1000
just train diffusion
just train smolvla
```

## 7) `just eval [model] [policy_path] [garment] [episodes] [dataset_root]`

执行脚本：`run_eval.sh`

参数说明（按顺序）：

1. `model`：默认 `act`
2. `policy_path`：默认值按模型映射  
   - `act` -> `outputs/train/act_top_long/checkpoints/last/pretrained_model`  
   - `diffusion` -> `outputs/train/dp_top_long/checkpoints/last/pretrained_model`  
   - `smolvla` -> `outputs/train/smolvla_top_long/checkpoints/last/pretrained_model`
3. `garment`：默认 `top_long`
4. `episodes`：默认 `5`
5. `dataset_root`：默认 `Datasets/example/<garment>_merged`
6. 其余参数会原样透传给 `python -m scripts.eval`

会做的事情：

1. 自动定位项目目录并激活 `.venv`。
2. 以 `lerobot` policy 方式调用 `python -m scripts.eval`。
3. 自动携带 `--dataset_root`（LeRobot 评估必需）。
4. 评估日志写入 `logs/` 目录。

示例：

```bash
just eval
just eval act outputs/train/act_top_long/checkpoints/last/pretrained_model top_long 5 Datasets/example/top_long_merged
just eval diffusion outputs/train/dp_top_long/checkpoints/last/pretrained_model top_short 3 Datasets/example/top_short_merged
just eval smolvla outputs/train/smolvla_top_long/checkpoints/last/pretrained_model top_long 5 Datasets/example/top_long_merged --task_description "fold the garment on the table"
```

## 常见执行顺序

```bash
just vpn      # 可选：先准备代理
just s1       # 基础安装
just s2       # 按官方步骤补全
just s3       # 环境授权与软链接
just save 1   # 备份当前状态到 v1
```

## 补充：`just setup`

虽然不在上面 5 条里，但 `just setup` 也很常用。它会按顺序执行：

```bash
just s1
just s2
just s3
```
