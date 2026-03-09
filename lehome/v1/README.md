# LeHome 主入口

`lehome/` 是当前项目的主力脚本目录。

这里保留的主入口：
- `allinone.sh`：统一总入口
- `prepare.sh`：环境准备
- `data.sh`：数据下载
- `train.sh`：训练包装入口
- `eval.sh`：评估包装入口
- `xvla.sh`：XVLA 专用入口
- `wandb.sh`：WandB 预检
- `sweep.sh`：WandB sweep 入口

旧的原始 `start/step*.sh` 已归档到 `lehome/v1/` 作为备份。

## 推荐顺序

1. `bash lehome/allinone.sh vpn`（可选）
2. `bash lehome/allinone.sh prepare [--install-system-libs]`
3. `bash lehome/allinone.sh data [--with-full-dataset]`
4. `bash lehome/allinone.sh train ...`
5. `bash lehome/allinone.sh eval ...`
6. `bash lehome/allinone.sh save <version>`

快速跑完整准备流程：

```bash
bash lehome/allinone.sh setup --install-system-libs --with-full-dataset
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
just sweep --dry-run --model xvla --steps 1000
just setup --install-system-libs --with-full-dataset
just save 1
```

## 说明

- `train.sh` / `eval.sh` 只是包装层，底层仍调用仓库根目录的 `run_train.sh` / `run_eval.sh`
- `allinone.sh` 会统一分发 `setup / prepare / data / train / eval / xvla / wandb / sweep / save / vpn`
- `xvla.sh` 仍保留 XVLA 的 install / train / eval 一体化体验
- `wandb.sh` 只做检查与展示，不直接启动训练
- `sweep.sh` 的底层调用脚本是 `scripts/wandb_sweep.py`
