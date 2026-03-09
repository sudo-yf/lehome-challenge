# Agent Operating Manual (LeHome Challenge 2026)

本文档是给自动化 Agent 的强约束执行手册。
目标：在 LeHome Challenge 2026 项目中，严格、可追溯、低风险地完成安装、训练、评估与提交流程。

## 1. 总原则

- 这是严谨的科学比赛，任何疏忽都可能导致比赛失败或科研误差。
- 必须以仓库 `docs/` 文档为第一依据，任何脚本行为都要与文档一致。
- 必须追求绝对严谨：先验证再执行，先解释风险再操作。
- 未经人工明确许可，禁止随意修改代码、依赖、虚拟环境或系统环境。
- 高危操作仅允许通过 `sh/bash` 命令执行，且必须先获得人工明确许可。
- 未经许可不得进行破坏性或不可逆操作。

## 2. 比赛背景（执行上下文）

- 比赛：**LeHome Challenge 2026**。
- 任务主题：家庭场景中的服装操作技能学习（garment manipulation）。
- 核心技术栈：IsaacLab + LeRobot。
- 主要流程：环境安装 -> 资产/数据集准备 -> 训练策略 -> 策略评估。
- 评估重点：按 garment 类型进行 episode 评估，LeRobot 策略需 `policy_path + dataset_root`。

## 3. 文档优先级（必须按此顺序理解）

1. `README.md`（项目入口与 just 命令说明）
2. `docs/installation.md`（环境安装）
3. `docs/training.md`（训练配置与参数语义）
4. `docs/policy_eval.md`（评估参数与路径规范）
5. `docs/datasets.md`（数据采集/处理）

若脚本与文档冲突：

- 先报告冲突点（文件 + 行号 + 差异）。
- 再给出修复建议与风险。
- 经人工确认后再改动。

## 4. 高危操作规范（强制）

下列行为视为高危：

- 删除/覆盖：`rm -rf`、批量覆盖、清空目录。
- Git 不可逆操作：`reset --hard`、强推、改 tag、改 remote、批量 rebase。
- 系统级安装/变更：`apt install/remove`、写系统路径、改用户 shell 启动脚本。
- 外部发布：`git push`、上传模型/数据到远端。

高危操作执行要求：

1. 必须使用 shell 命令执行（`sh`/`bash`）。
2. 必须先给出简洁风险说明。
3. 必须获得人工明确许可后才能执行。
4. 执行后必须回报结果与影响范围。

## 5. 训练与评估的严格约定

### 5.1 训练（run_train.sh / just train）

支持模型：

- `act`
- `diffusion`（兼容别名 `dp`）
- `smolvla`

支持 steps 覆盖写法（等价）：

- `just train act 1000`
- `just train act step1000`
- `just train act step 1000`
- `just train act steps=1000`
- `just train act --steps 1000`
- `just train act --max_steps 1000`

输出目录防覆盖策略：

- 若配置中的 `output_dir` 已存在且未显式指定 `--output_dir` 或 `--resume`，应报错退出。
- 续训示例：`just train act --resume=true --config_path outputs/train/act_top_long/train_config.json`

### 5.2 评估（run_eval.sh / just eval）

默认行为：

- `episodes` 默认 `5`
- `dataset_root` 默认 `Datasets/example/<garment>_merged`
- `policy_path` 必须指向 `.../checkpoints/last/pretrained_model`

模型到默认 policy 路径映射：

- `act` -> `outputs/train/act_top_long/checkpoints/last/pretrained_model`
- `diffusion` -> `outputs/train/dp_top_long/checkpoints/last/pretrained_model`
- `smolvla` -> `outputs/train/smolvla_top_long/checkpoints/last/pretrained_model`

SmolVLA 额外要求：

- 需提供 `--task_description`（脚本可自动补默认值）。

## 6. Just 命令知识库（必须了解）

项目当前主要命令：

- `just vpn` -> `bash start/step_vpn.sh`
- `just s1` -> `bash start/step1.sh`
- `just s2` -> `bash start/step2.sh`
- `just s3` -> `bash start/step3.sh`
- `just save <version>` -> `bash start/step_git.sh <version>`
- `just train ...` -> `bash run_train.sh ...`
- `just eval ...` -> `bash run_eval.sh ...`
- `just setup` -> 依次执行 `s1 -> s2 -> s3`

## 7. 标准执行流程（Agent 必须遵守）

1. 先阅读并引用相关文档段落。
2. 再检查现有脚本与配置（路径、默认值、参数格式）。
3. 给出最小改动方案（先解释再执行）。
4. 非高危操作可直接执行；高危操作先请求人工许可。
5. 每次改动后至少进行：语法检查 + 关键命令 dry-run/参数检查。
6. 汇报必须包含：改了什么、为什么、如何验证、剩余风险。

## 8. 禁止事项

- 禁止在未说明风险时直接执行高危命令。
- 禁止绕过文档随意改默认参数语义。
- 禁止静默修改提交、远端、标签、系统配置。
- 禁止把“可能破坏数据”的动作与普通训练/评估命令混在一起执行。

## 9. 输出要求（给人看的结果）

每次任务结束都应提供：

- 变更文件列表。
- 关键差异摘要。
- 实际验证命令与结果。
- 如果未完成，明确卡点与下一步建议。
