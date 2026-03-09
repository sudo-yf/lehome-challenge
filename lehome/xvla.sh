#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
source "$SCRIPT_DIR/wandb.sh"

# ==========================================
# 🛑 第一步：请在这里填入你的专属配置！
# ==========================================
HF_TOKEN="${HF_TOKEN:-YOUR_HUGGINGFACE_TOKEN_HERE}"
DATASET_REPO="${DATASET_REPO:-}"
DATASET_ROOT="${DATASET_ROOT:-}"
MY_ROBOT_REPO="${MY_ROBOT_REPO:-}"
WORK_MODE="${WORK_MODE:-train}"              # install / train / eval
INSTALL_SYSTEM_LIBS="${INSTALL_SYSTEM_LIBS:-false}"    # true / false
DOWNLOAD_FULL_DATASET="${DOWNLOAD_FULL_DATASET:-false}"  # true / false

PRETRAINED_PATH="${PRETRAINED_PATH:-}"
OUTPUT_DIR="${OUTPUT_DIR:-}"
TRAIN_STEPS="${TRAIN_STEPS:-}"
GARMENT_TYPE="${GARMENT_TYPE:-top_long}"
EVAL_EPISODES="${EVAL_EPISODES:-5}"
EVAL_POLICY_PATH="${EVAL_POLICY_PATH:-}"
TASK_DESCRIPTION="${TASK_DESCRIPTION:-fold the garment on the table}"
JOB_NAME="${JOB_NAME:-}"
DRY_RUN="${DRY_RUN:-false}"
CONFIG_TEMPLATE="${CONFIG_TEMPLATE:-}"

usage() {
    cat <<'USAGE'
Usage: bash lehome/xvla.sh

Edit the config block at the top of the script, then set:
- WORK_MODE=install  -> bootstrap LeHome env and verify X-VLA imports
- WORK_MODE=train    -> train X-VLA with a temp config derived from configs/train_xvla.yaml
- WORK_MODE=eval     -> evaluate a trained X-VLA checkpoint on LeHome garments
- DRY_RUN=true       -> only generate and display the final training config
USAGE
}

resolve_job_name() {
    local resolved_job_name="$JOB_NAME"

    if [[ -z "$resolved_job_name" && -n "$OUTPUT_DIR" ]]; then
        resolved_job_name="$(basename -- "$OUTPUT_DIR")"
    fi
    if [[ -z "$resolved_job_name" || "$resolved_job_name" == "." || "$resolved_job_name" == "/" ]]; then
        resolved_job_name="xvla_${GARMENT_TYPE}_$(date +'%Y%m%d_%H%M%S')"
    fi

    printf '%s\n' "$resolved_job_name"
}

yaml_value() {
    local key="$1"
    python - "$CONFIG_TEMPLATE" "$key" <<'PY'
from pathlib import Path
import sys
import yaml

config_path = Path(sys.argv[1])
key = sys.argv[2]
if not config_path.exists():
    raise SystemExit(1)
cur = yaml.safe_load(config_path.read_text())
for part in key.split('.'):
    cur = cur[part]
print(cur)
PY
}

load_defaults_from_config() {
    CONFIG_TEMPLATE="${PROJECT_ROOT}/configs/train_xvla.yaml"
    [[ -f "$CONFIG_TEMPLATE" ]] || die "❌ 找不到 X-VLA 配置模板: $CONFIG_TEMPLATE"

    if [[ -z "$DATASET_REPO" ]]; then
        DATASET_REPO="$(yaml_value dataset.repo_id)"
    fi
    if [[ -z "$DATASET_ROOT" ]]; then
        DATASET_ROOT="$(yaml_value dataset.root)"
    fi
    if [[ -z "$MY_ROBOT_REPO" ]]; then
        MY_ROBOT_REPO="$(yaml_value policy.repo_id)"
    fi
    if [[ -z "$PRETRAINED_PATH" ]]; then
        PRETRAINED_PATH="$(yaml_value policy.pretrained_path)"
    fi
    if [[ -z "$OUTPUT_DIR" ]]; then
        OUTPUT_DIR="$(yaml_value output_dir)"
    fi
    if [[ -z "$TRAIN_STEPS" ]]; then
        TRAIN_STEPS="$(yaml_value steps)"
    fi
    if [[ -z "$EVAL_POLICY_PATH" ]]; then
        EVAL_POLICY_PATH="${OUTPUT_DIR}/checkpoints/last/pretrained_model"
    fi
}

maybe_login_hf() {
    if [[ -n "$HF_TOKEN" && "$HF_TOKEN" != "YOUR_HUGGINGFACE_TOKEN_HERE" ]]; then
        if ! command -v hf >/dev/null 2>&1; then
            log "📦 安装 Hugging Face CLI..."
            uv pip install "huggingface_hub[cli]"
        fi
        log "🔑 登录 Hugging Face..."
        hf auth login --token "$HF_TOKEN" --add-to-git-credential
        ok "✅ Hugging Face 登录完成"
    else
        warn "⚠️ 未填写 HF_TOKEN，跳过 Hugging Face 登录。若需访问私有仓库，请补全。"
    fi
}

ensure_lehome_env() {
    ensure_repo_root
    ensure_path
    load_defaults_from_config
    [[ -f "$PROJECT_ROOT/.venv/bin/activate" ]] || die "❌ 未找到 $PROJECT_ROOT/.venv，请先执行 lehome/prepare.sh 或 lehome/allinone.sh setup"
    activate_venv
}

run_install() {
    ensure_repo_root
    ensure_path
    load_defaults_from_config

    local setup_args=()
    if [[ "$INSTALL_SYSTEM_LIBS" == "true" ]]; then
        setup_args+=(--install-system-libs)
    fi
    if [[ "$DOWNLOAD_FULL_DATASET" == "true" ]]; then
        setup_args+=(--with-full-dataset)
    fi

    log "🚀 开始按 LeHome v2 流程准备环境..."
    bash "/allinone.sh" setup "${setup_args[@]}"

    activate_venv
    python -c "import lerobot.policies.xvla; print('X-VLA import ok')"
    maybe_login_hf
    ok "✅ X-VLA 环境准备完成"
}

run_train() {
    ensure_lehome_env
    maybe_login_hf
    DRY_RUN="$(normalize_bool "$DRY_RUN" "DRY_RUN")"
    wandb_preflight_train

    local resolved_job_name
    resolved_job_name="$(resolve_job_name)"
    local wandb_enabled
    wandb_enabled="$(wandb_effective_enable)"

    local tmp_config
    tmp_config="$(mktemp /tmp/train_xvla_XXXX.yaml)"
    if [[ "$DRY_RUN" != "true" ]]; then
        trap 'rm -f "$tmp_config"' EXIT
    fi

    XVLA_CONFIG_TEMPLATE="$PROJECT_ROOT/configs/train_xvla.yaml" \
    XVLA_TMP_CONFIG="$tmp_config" \
    XVLA_DATASET_REPO="$DATASET_REPO" \
    XVLA_DATASET_ROOT="$DATASET_ROOT" \
    XVLA_MODEL_REPO="$MY_ROBOT_REPO" \
    XVLA_PRETRAINED_PATH="$PRETRAINED_PATH" \
    XVLA_OUTPUT_DIR="$OUTPUT_DIR" \
    XVLA_TRAIN_STEPS="$TRAIN_STEPS" \
    XVLA_JOB_NAME="$resolved_job_name" \
    XVLA_WANDB_ENABLE="$wandb_enabled" \
    XVLA_WANDB_PROJECT="$WANDB_PROJECT" \
    XVLA_WANDB_ENTITY="$WANDB_ENTITY" \
    XVLA_WANDB_NOTES="$WANDB_NOTES" \
    XVLA_WANDB_RUN_ID="$WANDB_RUN_ID" \
    XVLA_WANDB_MODE="$WANDB_MODE" \
    XVLA_WANDB_DISABLE_ARTIFACT="$WANDB_DISABLE_ARTIFACT" \
    python - <<'PY'
import os
import yaml

def maybe_none(value: str):
    return value if value else None

src = os.environ["XVLA_CONFIG_TEMPLATE"]
dst = os.environ["XVLA_TMP_CONFIG"]
with open(src, 'r', encoding='utf-8') as f:
    data = yaml.safe_load(f)

data['dataset']['repo_id'] = os.environ['XVLA_DATASET_REPO']
data['dataset']['root'] = os.environ['XVLA_DATASET_ROOT']
data['policy']['repo_id'] = os.environ['XVLA_MODEL_REPO']
data['policy']['pretrained_path'] = os.environ['XVLA_PRETRAINED_PATH']
data['output_dir'] = os.environ['XVLA_OUTPUT_DIR']
data['steps'] = int(os.environ['XVLA_TRAIN_STEPS'])
data['job_name'] = os.environ['XVLA_JOB_NAME']

wandb_cfg = data.setdefault('wandb', {})
wandb_cfg['enable'] = os.environ['XVLA_WANDB_ENABLE'].lower() == 'true'
wandb_cfg['project'] = os.environ['XVLA_WANDB_PROJECT']
wandb_cfg['entity'] = maybe_none(os.environ['XVLA_WANDB_ENTITY'])
wandb_cfg['notes'] = maybe_none(os.environ['XVLA_WANDB_NOTES'])
wandb_cfg['run_id'] = maybe_none(os.environ['XVLA_WANDB_RUN_ID'])
wandb_cfg['mode'] = os.environ['XVLA_WANDB_MODE']
wandb_cfg['disable_artifact'] = os.environ['XVLA_WANDB_DISABLE_ARTIFACT'].lower() == 'true'

with open(dst, 'w', encoding='utf-8') as f:
    yaml.safe_dump(data, f, sort_keys=False, allow_unicode=True)
PY

    log "🔥 正在启动 X-VLA 训练..."
    log "📄 临时配置: $tmp_config"
    log "📦 数据集仓库: $DATASET_REPO"
    log "📁 数据集路径: $DATASET_ROOT"
    log "🤖 模型仓库: $MY_ROBOT_REPO"
    log "🗂️ 输出目录: $OUTPUT_DIR"
    log "⏱️ 训练步数: $TRAIN_STEPS"
    wandb_print_summary "$resolved_job_name"

    if [[ "$DRY_RUN" == "true" ]]; then
        log "🧪 DRY_RUN 已开启，未真正启动训练。"
        log "📄 已保留临时配置: $tmp_config"
        log "🧾 最终命令: lerobot-train --config_path=$tmp_config"
        return 0
    fi

    lerobot-train --config_path="$tmp_config"
}

run_eval() {
    ensure_lehome_env

    if ! command -v xvfb-run >/dev/null 2>&1; then
        die "❌ 未找到 xvfb-run，无法执行 X-VLA 评估。"
    fi
    if [[ ! -d "$EVAL_POLICY_PATH" ]]; then
        die "❌ 评估模型路径不存在: $EVAL_POLICY_PATH"
    fi

    log "🧪 正在启动 X-VLA 评估..."
    log "📦 模型路径: $EVAL_POLICY_PATH"
    log "📚 数据路径: $DATASET_ROOT"

    xvfb-run -a python -m scripts.eval \
        --policy_type lerobot \
        --policy_path "$EVAL_POLICY_PATH" \
        --dataset_root "$DATASET_ROOT" \
        --garment_type "$GARMENT_TYPE" \
        --num_episodes "$EVAL_EPISODES" \
        --task_description "$TASK_DESCRIPTION" \
        --enable_cameras \
        --device cpu \
        --headless
}

main() {
    case "$WORK_MODE" in
        install)
            run_install
            ;;
        train)
            run_train
            ;;
        eval)
            run_eval
            ;;
        -h|--help|help)
            usage
            ;;
        *)
            die "❌ 不支持的 WORK_MODE: $WORK_MODE（可选: install / train / eval）"
            ;;
    esac
}

main "$@"
