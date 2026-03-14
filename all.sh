#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$SCRIPT_DIR/pyproject.toml" ]]; then
  ROOT_DIR="$SCRIPT_DIR"
else
  ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
fi
LOG_DIR="$ROOT_DIR/logs"
mkdir -p "$LOG_DIR"

# ── env.sh 框架变量 ──────────────────────────────────────────────────────────
MODE="confirm"
ASSUME_YES=0
DRY_RUN=0
WRITE_BASHRC=0
LIST_ONLY=0
HAS_GUM=0
LOG_FILE="$LOG_DIR/all-step-runner-$(date +%Y%m%d-%H%M%S).log"
SUCCESS_COUNT=0
SKIPPED_COUNT=0
FAILED_COUNT=0
REQUESTED_STEP_IDS=()
STEP_IDS=()
STEP_TITLES=()
STEP_TYPES=()
STEP_RISKS=()
STEP_DEFAULTS=()
STEP_HANDLERS=()
STEP_COMMANDS=()
STEP_DESCS=()

export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"

# ── 颜色定义 (v1/common.sh) ──────────────────────────────────────────────────
BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
GRAY='\033[90m'
WHITE='\033[97m'
NC='\033[0m'

# ── 日志 ─────────────────────────────────────────────────────────────────────
log_line() { printf '[%s] %s\n' "$(date '+%F %T')" "$*" >>"$LOG_FILE"; }
log()  { echo -e "${BLUE}$*${NC}"; }
ok()   { echo -e "${GREEN}$*${NC}"; }
warn() { echo -e "${YELLOW}$*${NC}"; }
die()  { echo -e "${RED}$*${NC}" >&2; exit 1; }
rule() { printf '%b%s%b\n' "$BLUE" "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" "$NC"; }
section() { echo; rule; log "▶ $*"; rule; }
kv() { local key="$1"; shift; printf '%b%-18s%b %s\n' "$BLUE" "${key}:" "$NC" "$*"; }
cmd_preview() { log "💻 $*"; }

# ── style_* (env.sh 兼容) ────────────────────────────────────────────────────
style_dim()  { [[ "$HAS_GUM" -eq 1 ]] && gum style --foreground 245 "$*" || echo "$*"; }
style_ok()   { [[ "$HAS_GUM" -eq 1 ]] && gum style --foreground 46  "$*" || echo "$*"; }
style_warn() { [[ "$HAS_GUM" -eq 1 ]] && gum style --foreground 214 "$*" || echo "$*"; }
style_err()  { [[ "$HAS_GUM" -eq 1 ]] && gum style --foreground 196 "$*" || echo "$*" >&2; }

# ── UI 函数 (env.sh) ─────────────────────────────────────────────────────────
ui_confirm() {
  local prompt="$1" default_yes="${2:-1}"
  [[ "$ASSUME_YES" -eq 1 ]] && return 0
  if [[ "$HAS_GUM" -eq 1 ]]; then
    if [[ "$default_yes" -eq 1 ]]; then
      gum confirm --affirmative "执行" --negative "跳过" --default=true "$prompt"
    else
      gum confirm --affirmative "确认" --negative "取消" --default=false "$prompt"
    fi
    return $?
  fi
  local ans
  if [[ "$default_yes" -eq 1 ]]; then
    read -r -p "$prompt [Y/n]: " ans; ans="${ans:-Y}"
  else
    read -r -p "$prompt [y/N]: " ans; ans="${ans:-N}"
  fi
  case "${ans,,}" in y|yes) return 0 ;; *) return 1 ;; esac
}

ui_choose_one() {
  local header="$1"; shift; local options=("$@")
  if [[ "$HAS_GUM" -eq 1 ]]; then
    printf '%s\n' "${options[@]}" | gum choose --header "$header" || true; return
  fi
  echo "$header"; local i=1
  for opt in "${options[@]}"; do echo "  $i) $opt"; i=$((i+1)); done
  local idx; read -r -p "请输入序号: " idx
  if [[ "$idx" =~ ^[0-9]+$ ]] && ((idx >= 1 && idx <= ${#options[@]})); then
    echo "${options[$((idx-1))]}"; fi
}

ui_choose_many_lines() {
  local header="$1"; shift; local options=("$@")
  if [[ "$HAS_GUM" -eq 1 ]]; then
    printf '%s\n' "${options[@]}" | gum choose --no-limit --ordered --header "$header\n空格选中，回车确认" || true; return
  fi
  echo "$header"; local i=1
  for opt in "${options[@]}"; do echo "  $i) $opt"; i=$((i+1)); done
  read -r -p "输入序号（逗号分隔，如 1,3,5）: " raw
  IFS=',' read -r -a picks <<<"$raw"
  for p in "${picks[@]}"; do
    p="${p//[[:space:]]/}"
    if [[ "$p" =~ ^[0-9]+$ ]] && ((p >= 1 && p <= ${#options[@]})); then
      echo "${options[$((p-1))]}"; fi
  done
}

# ── 工具函数 ─────────────────────────────────────────────────────────────────
badge_for_type() { case "$1" in official) printf '官方';; enhanced) printf '增强(非官方)';; *) printf '其他';; esac; }
risk_badge()     { case "$1" in low) printf '低';; medium) printf '中';; high) printf '高';; *) printf '未知';; esac; }

ensure_project_root() {
  [[ -f "$ROOT_DIR/pyproject.toml" ]] || { style_err "未找到项目根目录: $ROOT_DIR"; exit 1; }
  cd "$ROOT_DIR"
}
ensure_repo_root() { ensure_project_root; }
ensure_path() { export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"; }

activate_venv() {
  [[ -f "$ROOT_DIR/.venv/bin/activate" ]] || { style_err "未找到虚拟环境: $ROOT_DIR/.venv/bin/activate"; return 1; }
  export PS1="${PS1-}"; set +u
  # shellcheck disable=SC1091
  source "$ROOT_DIR/.venv/bin/activate"; set -u
}

require_cmd() {
  local cmd="$1"
  command -v "$cmd" >/dev/null 2>&1 || { style_err "缺少命令: $cmd"; return 1; }
}

backup_file() {
  local path="$1"; [[ -e "$path" ]] || return 0
  cp "$path" "$path.bak.$(date +%Y%m%d_%H%M%S)"
}

safe_symlink() {
  local target="$1" link_path="$2"
  mkdir -p "$(dirname -- "$link_path")"
  if [[ -L "$link_path" ]]; then
    local current; current="$(readlink -f "$link_path" || true)"
    if [[ "$current" == "$(readlink -f "$target")" ]]; then
      ok "✅ 软链接已存在: $link_path -> $target"; return 0; fi
    rm -f "$link_path"
  elif [[ -e "$link_path" ]]; then
    mv "$link_path" "$link_path.bak.$(date +%Y%m%d_%H%M%S)"; fi
  ln -s "$target" "$link_path"
  ok "✅ 已建立软链接: $link_path -> $target"
}

ensure_uv() {
  ensure_path
  if ! command -v uv >/dev/null 2>&1; then
    section "安装 uv"; cmd_preview 'curl -LsSf https://astral.sh/uv/install.sh | sh'
    curl -LsSf https://astral.sh/uv/install.sh | sh; ensure_path; fi
  ok "✅ uv 已就绪: $(command -v uv)"
}

link_uv_cache() {
  local target="/root/data/.uv_cache" link_path="$HOME/.cache/uv"
  mkdir -p "$target" "$HOME/.cache"
  if [[ -L "$link_path" ]]; then
    local current; current="$(readlink -f "$link_path")"
    if [[ "$current" == "$target" ]]; then ok "✅ UV 缓存软链接已存在"; return 0; fi
    rm -f "$link_path"
  elif [[ -e "$link_path" ]]; then
    die "❌ $link_path 已存在且不是软链接，请先手动处理。"; fi
  ln -s "$target" "$link_path"; ok "✅ 已建立缓存软链接: $link_path -> $target"
}

install_system_libs() {
  local priv_cmd=(); [[ "$(id -u)" -eq 0 ]] || priv_cmd=(sudo)
  section "安装系统图形库"
  "${priv_cmd[@]}" apt update
  "${priv_cmd[@]}" apt install -y libglu1-mesa libgl1 libegl1 libxrandr2 libxinerama1 libxcursor1 libxi6 libxext6 libx11-6
  export __GLX_VENDOR_LIBRARY_NAME=nvidia; ok "✅ 系统库安装完成"
}

clone_isaaclab_if_missing() {
  mkdir -p "$ROOT_DIR/third_party"
  if [[ ! -d "$ROOT_DIR/third_party/IsaacLab" ]]; then
    section "克隆 IsaacLab"
    cmd_preview 'git clone https://github.com/lehome-official/IsaacLab.git third_party/IsaacLab'
    git clone https://github.com/lehome-official/IsaacLab.git "$ROOT_DIR/third_party/IsaacLab"; fi
  ok "✅ IsaacLab 目录已就绪"
}

check_imports() {
  python - "$@" <<'PY'
import importlib, sys
failed = {}
for name in sys.argv[1:]:
    try: importlib.import_module(name)
    except Exception as exc: failed[name] = f"{type(exc).__name__}: {exc}"
if failed:
    for k, v in failed.items(): print(f"{k}: {v}")
    raise SystemExit(1)
print("All imports passed:", ", ".join(sys.argv[1:]))
PY
}

local_script_path()  { printf '%s/%s\n' "$SCRIPT_DIR" "$1"; }
repo_script_path()   { printf '%s/%s\n' "$ROOT_DIR"   "$1"; }
invoke_local_script() { local s="$1"; shift; bash "$(local_script_path "$s")" "$@"; }
exec_local_script()   { local s="$1"; shift; exec bash "$(local_script_path "$s")" "$@"; }
invoke_repo_script()  { local s="$1"; shift; ensure_repo_root; bash "$(repo_script_path "$s")" "$@"; }
exec_repo_script()    { local s="$1"; shift; ensure_repo_root; exec bash "$(repo_script_path "$s")" "$@"; }

# ── Step 注册框架 (env.sh) ───────────────────────────────────────────────────
add_step() {
  STEP_IDS+=("$1"); STEP_TITLES+=("$2"); STEP_TYPES+=("$3"); STEP_RISKS+=("$4")
  STEP_DEFAULTS+=("$5"); STEP_HANDLERS+=("$6"); STEP_COMMANDS+=("$7"); STEP_DESCS+=("$8")
}

find_step_idx_by_id() {
  local target="$1" idx
  for idx in "${!STEP_IDS[@]}"; do
    [[ "${STEP_IDS[$idx]}" == "$target" ]] && { echo "$idx"; return 0; }; done
  return 1
}

show_banner() {
  cat <<'EOF'
╭──────────────────────────────────────────╮
│          LeHome Setup Assistant          │
│      AI Environment & Training Tool      │
╰──────────────────────────────────────────╯

请选择操作：

[ Quick Start ]

> 1. 执行全流程（推荐）
    自动完成环境准备、IsaacLab / LeHome 安装、资源下载与基础配置


[ Environment Setup ]

  2. 环境准备
    安装 uv、同步依赖、安装 IsaacLab / LeHome、执行导入校验与 EULA 及软链修复

  3. 数据资源管理
    下载 Assets 与示例数据集，可选完整 dataset_challenge


[ Training Workspace ]

  4. X-VLA 工作台
    初始化训练环境、生成训练配置并支持训练 / 评估


[ Developer Tools ]

  5. AI 开发工具链
    安装 Codex / Claude Code / ZCF / Happy Coder

  6. github配置与Shell 快捷命令
    写入 go / train / eval / save / diff 命令并补充 PATH

[ Network ]

  7 VPN 与代理配置
    部署 Clash for Linux、写入订阅配置并输出代理端口信息


  0. 退出

──────────────────────────────────────────
使用 ↑ ↓ 选择，Enter 确认
或输入编号直接进入对应模块
EOF
}

show_compact_main_menu_header() {
  cat <<'EOF'
╭──────────────────────────────────────────╮
│          LeHome Setup Assistant          │
│      AI Environment & Training Tool      │
╰──────────────────────────────────────────╯

Quick Start          : 1 执行全流程（推荐）
Environment Setup    : 2 环境准备 / 3 数据资源管理
Training Workspace   : 4 X-VLA 工作台
Developer Tools      : 5 AI 开发工具链 / 6 github配置与Shell 快捷命令
Network              : 7 VPN 与代理配置

使用 ↑ ↓ 选择，Enter 确认
EOF
}

show_steps_table() {
  local idx
  for idx in "${!STEP_IDS[@]}"; do
    local num=$((idx+1)) type risk default_mark=""
    type="$(badge_for_type "${STEP_TYPES[$idx]}")"; risk="$(risk_badge "${STEP_RISKS[$idx]}")"
    [[ "${STEP_DEFAULTS[$idx]}" == "1" ]] && default_mark="默认"
    echo "$num. ${STEP_IDS[$idx]} [$type][风险:$risk] $default_mark"
    echo "   ${STEP_TITLES[$idx]}"
    echo "   命令: ${STEP_COMMANDS[$idx]}"
    echo "   说明: ${STEP_DESCS[$idx]}"; done
}
show_step_list_only() { show_steps_table; }
is_high_risk() { [[ "$1" == "high" ]]; }

run_step_handler() {
  local handler="$1"
  declare -f "$handler" >/dev/null 2>&1 || { style_err "内部错误：未找到步骤函数 $handler"; return 1; }
  "$handler"
}

record_success() { SUCCESS_COUNT=$((SUCCESS_COUNT+1)); }
record_skip()    { SKIPPED_COUNT=$((SKIPPED_COUNT+1)); }
record_failure() { FAILED_COUNT=$((FAILED_COUNT+1)); }

choose_failure_action() {
  if [[ "$HAS_GUM" -eq 1 ]]; then
    printf '重试\n跳过\n终止' | gum choose --header "步骤失败，选择后续操作" || echo "终止"; return; fi
  echo "步骤失败，选择后续操作:"; echo "1) 重试"; echo "2) 跳过"; echo "3) 终止"
  local c; read -r -p "请输入序号: " c
  case "$c" in 1) echo "重试";; 2) echo "跳过";; *) echo "终止";; esac
}

run_step_by_idx() {
  local idx="$1" id title type risk handler cmd
  id="${STEP_IDS[$idx]}"; title="${STEP_TITLES[$idx]}"; type="${STEP_TYPES[$idx]}"
  risk="${STEP_RISKS[$idx]}"; handler="${STEP_HANDLERS[$idx]}"; cmd="${STEP_COMMANDS[$idx]}"
  echo; style_dim "Step $((idx+1)) | $id | $(badge_for_type "$type") | 风险: $(risk_badge "$risk")"
  style_dim "标题: $title"; style_dim "命令: $cmd"
  log_line "准备执行 step=$id type=$type risk=$risk"
  case "$id" in
    train_xvla|eval_xvla|train_guide)
      ensure_train_xvla_yaml || return 1
      ;;
  esac
  if [[ "$DRY_RUN" -eq 1 ]]; then style_dim "DRY RUN: 未执行"; record_skip; log_line "DRY_RUN 跳过 step=$id"; return 0; fi
  if [[ "$MODE" == "confirm" ]]; then
    if ! ui_confirm "执行步骤 $id 吗？" 1; then
      style_warn "已跳过 $id"; record_skip; log_line "用户跳过 step=$id"; return 0; fi; fi
  if is_high_risk "$risk"; then
    if ! ui_confirm "高风险步骤：$id。确认继续？" 0; then
      style_warn "已跳过高风险步骤 $id"; record_skip; log_line "用户取消高风险 step=$id"; return 0; fi; fi
  while true; do
    set +e; run_step_handler "$handler"; local status=$?; set -e
    if [[ $status -eq 0 ]]; then style_ok "完成: $id"; record_success; log_line "完成 step=$id"; return 0; fi
    style_err "失败: $id (exit=$status)"; log_line "失败 step=$id exit=$status"
    if [[ "$MODE" == "auto" || "$ASSUME_YES" -eq 1 ]]; then record_failure; return "$status"; fi
    local action; action="$(choose_failure_action)"
    case "$action" in 重试) ;; 跳过) record_skip; log_line "失败后跳过 step=$id"; return 0;;
      终止|*) record_failure; return "$status";; esac; done
}

run_default_flow() {
  local idx
  for idx in "${!STEP_IDS[@]}"; do
    [[ "${STEP_DEFAULTS[$idx]}" != "1" ]] && continue
    run_step_by_idx "$idx" || return 1; done
}

run_steps_by_ids() {
  local sid idx
  for sid in "$@"; do
    idx="$(find_step_idx_by_id "$sid")" || { style_err "未知步骤 ID: $sid"; return 1; }
    run_step_by_idx "$idx" || return 1; done
}

run_multi_select() {
  local options=() idx
  for idx in "${!STEP_IDS[@]}"; do
    options+=("${STEP_IDS[$idx]} | $(badge_for_type "${STEP_TYPES[$idx]}") | 风险:$(risk_badge "${STEP_RISKS[$idx]}") | ${STEP_TITLES[$idx]}"); done
  local picked_lines; picked_lines="$(ui_choose_many_lines "选择要执行的步骤" "${options[@]}")"
  [[ -z "$picked_lines" ]] && { style_warn "未选择任何步骤"; return 0; }
  local selected_ids=() line
  while IFS= read -r line; do [[ -z "$line" ]] && continue; selected_ids+=("${line%% | *}"); done <<<"$picked_lines"
  [[ ${#selected_ids[@]} -eq 0 ]] && { style_warn "未解析到有效步骤"; return 0; }
  run_steps_by_ids "${selected_ids[@]}"
}

set_mode_interactive() {
  local choice; choice="$(ui_choose_one "选择执行模式" "逐步确认（每步询问）" "自动执行（不再询问）")"
  case "$choice" in "自动执行（不再询问）") MODE="auto"; ASSUME_YES=1;; *) MODE="confirm"; ASSUME_YES=0;; esac
  style_dim "当前执行模式: $MODE"; log_line "执行模式切换为 $MODE"
}

ui_choose_numbered_option() {
  local header="$1"
  shift
  local options=("$@")
  if [[ "$HAS_GUM" -eq 1 ]]; then
    local picked
    picked="$(printf '%s\n' "${options[@]}" | gum choose --header "$header" || true)"
    [[ -n "$picked" ]] && printf '%s\n' "${picked%%.*}"
    return
  fi
  [[ -n "$header" ]] && echo "$header"
  local raw
  read -r -p "请输入编号: " raw
  if [[ "$raw" =~ ^([0-9]+) ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
  fi
}

wizard_section() {
  echo
  echo "================================================"
  echo "  $1"
  echo "================================================"
}

wizard_prompt_value() {
  local label="$1" default_display="$2" default_value="$3" result_var="$4"
  local input value
  printf "  %-16s ${GRAY}[%s]${NC} " "${label}:" "$default_display"
  read -r input
  value="${input:-$default_value}"
  if [[ -t 1 ]]; then
    printf '\033[1A\r\033[2K  %-16s %b%s%b\n' "${label}:" "${WHITE}" "$value" "${NC}"
  else
    printf "  %-16s ${WHITE}%s${NC}\n" "${label}:" "$value"
  fi
  printf -v "$result_var" '%s' "$value"
}

wizard_prompt_optional() {
  local label="$1" placeholder="$2" result_var="$3"
  local input
  printf "  %-16s ${GRAY}[%s]${NC} " "${label}:" "$placeholder"
  read -r input
  if [[ -t 1 ]]; then
    if [[ -n "$input" ]]; then
      printf '\033[1A\r\033[2K  %-16s %b%s%b\n' "${label}:" "${WHITE}" "$input" "${NC}"
    else
      printf '\033[1A\r\033[2K  %-16s %b<empty>%b\n' "${label}:" "${GRAY}" "${NC}"
    fi
  else
    if [[ -n "$input" ]]; then
      printf "  %-16s ${WHITE}%s${NC}\n" "${label}:" "$input"
    else
      printf "  %-16s ${GRAY}<empty>${NC}\n" "${label}:"
    fi
  fi
  printf -v "$result_var" '%s' "$input"
}

write_default_train_xvla_yaml() {
  local path="$1"
  mkdir -p "$(dirname "$path")"
  cat >"$path" <<'EOF'
# X-VLA Final Valid Config for Lehome
# Precision-aligned with official checkpoint

dataset:
  repo_id: lehome/dataset_challenge_merged
  root: Datasets/example/top_long_merged
  video_backend: torchcodec
  use_imagenet_stats: true
  image_transforms:
    enable: true
    max_num_transforms: 3
    random_order: false
    tfs:
      brightness:
        weight: 1.0
        type: ColorJitter
        kwargs:
          brightness: [0.8, 1.2]
      contrast:
        weight: 1.0
        type: ColorJitter
        kwargs:
          contrast: [0.8, 1.2]
      saturation:
        weight: 1.0
        type: ColorJitter
        kwargs:
          saturation: [0.5, 1.5]
      hue:
        weight: 1.0
        type: ColorJitter
        kwargs:
          hue: [-0.05, 0.05]
      sharpness:
        weight: 1.0
        type: SharpnessJitter
        kwargs:
          sharpness: [0.5, 1.5]

policy:
  type: xvla
  repo_id: lehome/xvla_so100
  push_to_hub: false
  pretrained_path: lerobot/xvla-base
  n_action_steps: 30
  chunk_size: 30
  empty_cameras: 0
  action_mode: auto
  max_action_dim: 20
  max_state_dim: 20
  num_image_views: 3
  resize_imgs_with_padding: [224, 224]
  dtype: bfloat16
  florence_config:
    projection_dim: 1024
    vision_config:
      model_type: davit
      image_size: 224
      projection_dim: 1024
      patch_size: [7, 3, 3, 3]
      patch_stride: [4, 2, 2, 2]
      patch_padding: [3, 1, 1, 1]
      patch_prenorm: [false, true, true, true]
      dim_embed: [256, 512, 1024, 2048]
      num_heads: [8, 16, 32, 64]
      num_groups: [8, 16, 32, 64]
      depths: [1, 1, 9, 1]
      window_size: 12
      image_pos_embed:
        type: learned_abs_2d
        max_pos_embeddings: 50
      visual_temporal_embedding:
        type: COSINE
        max_temporal_embeddings: 100
      image_feature_source: ["spatial_avg_pool", "temporal_avg_pool"]
    text_config:
      vocab_size: 51289
      d_model: 1024
      encoder_layers: 12
      decoder_layers: 12
      encoder_attention_heads: 16
      decoder_attention_heads: 16
      max_position_embeddings: 4096
  freeze_vision_encoder: false
  freeze_language_encoder: false
  train_policy_transformer: true
  train_soft_prompts: true
  input_features:
    observation.state:
      type: STATE
      shape: [12]
    observation.images.top_rgb:
      type: VISUAL
      shape: [3, 480, 640]
    observation.images.left_rgb:
      type: VISUAL
      shape: [3, 480, 640]
    observation.images.right_rgb:
      type: VISUAL
      shape: [3, 480, 640]
  output_features:
    action:
      type: ACTION
      shape: [12]

output_dir: outputs/train/top_long/xvla_base_3w_steps_final
batch_size: 8
steps: 30000
save_freq: 5000
eval_freq: 5000
log_freq: 1000
save_checkpoint: true

optimizer:
  type: xvla-adamw
  lr: 2e-5
  weight_decay: 1e-4
  betas: [0.9, 0.999]
  eps: 1e-8
  grad_clip_norm: 10.0

scheduler:
  type: cosine_decay_with_warmup
  num_warmup_steps: 1000
  num_decay_steps: 29000
  peak_lr: 2e-5
  decay_lr: 0.0

wandb:
  enable: false
  project: lehome_xvla
  mode: disabled
EOF
}

ensure_train_xvla_yaml() {
  local path="$ROOT_DIR/configs/train_xvla.yaml"
  [[ -f "$path" ]] && return 0
  warn "⚠️ 未找到 $path，正在自动生成默认 X-VLA 配置模板。"
  write_default_train_xvla_yaml "$path"
}

run_data_download_mode() {
  local with_full="$1"
  local old_value="${DATA_WITH_FULL_DATASET-__unset__}"
  DATA_WITH_FULL_DATASET="$with_full"
  run_steps_by_ids "data_download"
  local status=$?
  if [[ "$old_value" == "__unset__" ]]; then
    unset DATA_WITH_FULL_DATASET
  else
    DATA_WITH_FULL_DATASET="$old_value"
  fi
  return "$status"
}

run_shell_shortcuts_step() {
  local old_write_bashrc="$WRITE_BASHRC"
  WRITE_BASHRC=1
  run_steps_by_ids "write_shell_shortcuts"
  local status=$?
  WRITE_BASHRC="$old_write_bashrc"
  return "$status"
}

print_data_resources_menu() {
  cat <<'EOF'
[ 数据资源管理 ]

  1. 下载基础资源
     下载 Assets 与示例数据集

  2. 下载完整数据集
     额外下载 dataset_challenge（含 depth 信息）

  0. 返回
EOF
}

print_training_workspace_menu() {
  cat <<'EOF'
[ X-VLA 工作台 ]

  1. 初始化 X-VLA 环境
     完成环境准备、导入校验并给出训练 / 评估命令提示

  2. 交互式训练向导
     按参数向导生成训练配置并启动训练

  3. 交互式评估向导
     按参数向导生成评估命令并启动评估

  0. 返回
EOF
}

print_dev_tools_menu() {
  cat <<'EOF'
[ github配置与Shell 快捷命令 ]

  1. 写入 Shell 快捷命令
     写入 go / train / eval / save / diff 命令并补充 PATH

  2. GitHub / Git 基础配置
     初始化 Git 身份并检查远端仓库

  3. 保存新版本
     执行版本保存流程并刷新版本索引

  4. 生成 diff 日志
     对比 upstream/main 并输出 diff.log

  0. 返回
EOF
}

print_xvla_workspace_hints() {
  section "X-VLA 工作台"
  style_ok "X-VLA 初始化完成，可继续执行以下命令："
  style_dim "训练: bash \"$ROOT_DIR/all.sh\" --step train_xvla"
  style_dim "评估: bash \"$ROOT_DIR/all.sh\" --step eval_xvla"
}

run_module_full_flow() {
  run_steps_by_ids "prepare_full" || return 1
  run_data_download_mode 0 || return 1
  run_shell_shortcuts_step || return 1
}

run_module_environment_setup() {
  run_steps_by_ids "prepare_full"
}

run_module_data_resources() {
  while true; do
    echo
    local choice
    if [[ "$HAS_GUM" -eq 1 ]]; then
      choice="$(ui_choose_numbered_option "[ 数据资源管理 ]" \
        "1. 下载基础资源 - 下载 Assets 与示例数据集" \
        "2. 下载完整数据集 - 额外下载 dataset_challenge（含 depth 信息）" \
        "0. 返回")"
    else
      print_data_resources_menu
      choice="$(ui_choose_numbered_option "" "1. 下载基础资源" "2. 下载完整数据集" "0. 返回")"
    fi
    case "$choice" in
      1) run_data_download_mode 0 || return 1 ;;
      2) run_data_download_mode 1 || return 1 ;;
      0|"") return 0 ;;
      *) style_warn "无效选项: $choice" ;;
    esac
  done
}

run_module_xvla_workspace() {
  while true; do
    echo
    local choice
    if [[ "$HAS_GUM" -eq 1 ]]; then
      choice="$(ui_choose_numbered_option "[ X-VLA 工作台 ]" \
        "1. 初始化 X-VLA 环境 - 完成环境准备并校验导入" \
        "2. 交互式训练向导 - 生成训练配置并启动训练" \
        "3. 交互式评估向导 - 生成评估命令并启动评估" \
        "0. 返回")"
    else
      print_training_workspace_menu
      choice="$(ui_choose_numbered_option "" \
        "1. 初始化 X-VLA 环境" \
        "2. 交互式训练向导" \
        "3. 交互式评估向导" \
        "0. 返回")"
    fi
    case "$choice" in
      1)
        run_steps_by_ids "prepare_full" || return 1
        if [[ "$DRY_RUN" -eq 1 ]]; then
          style_dim "DRY RUN: 跳过 X-VLA 导入校验"
        else
          ensure_project_root
          activate_venv
          python -c "import lerobot.policies.xvla; print('X-VLA import ok')"
        fi
        print_xvla_workspace_hints
        ;;
      2) run_steps_by_ids "train_guide" || return 1 ;;
      3) run_steps_by_ids "eval_guide" || return 1 ;;
      0|"") return 0 ;;
      *) style_warn "无效选项: $choice" ;;
    esac
  done
}

run_module_ai_tools() {
  run_steps_by_ids "ai_tools"
}

run_module_dev_tools() {
  while true; do
    echo
    local choice
    if [[ "$HAS_GUM" -eq 1 ]]; then
      choice="$(ui_choose_numbered_option "[ github配置与Shell 快捷命令 ]" \
        "1. 写入 Shell 快捷命令 - 写入 go / train / eval / save / diff 命令并补充 PATH" \
        "2. GitHub / Git 基础配置 - 初始化 Git 身份并检查远端仓库" \
        "3. 保存新版本 - 执行版本保存流程并刷新版本索引" \
        "4. 生成 diff 日志 - 对比 upstream/main 并输出 diff.log" \
        "0. 返回")"
    else
      print_dev_tools_menu
      choice="$(ui_choose_numbered_option "" "1. 写入 Shell 快捷命令" "2. GitHub / Git 基础配置" "3. 保存新版本" "4. 生成 diff 日志" "0. 返回")"
    fi
    case "$choice" in
      1) run_shell_shortcuts_step || return 1 ;;
      2) run_steps_by_ids "git_basic_setup" || return 1 ;;
      3) run_steps_by_ids "save_version" || return 1 ;;
      4) run_steps_by_ids "diff" || return 1 ;;
      0|"") return 0 ;;
      *) style_warn "无效选项: $choice" ;;
    esac
  done
}

run_module_vpn() {
  run_steps_by_ids "vpn_setup"
}

print_summary() {
  echo; style_dim "执行摘要: success=$SUCCESS_COUNT skip=$SKIPPED_COUNT failed=$FAILED_COUNT"
  style_dim "日志文件: $LOG_FILE"
  [[ "$WRITE_BASHRC" -eq 0 ]] && style_dim "提示: 默认未改写 ~/.bashrc（如需写入请加 --write-bashrc）"
}

# ── Step 处理函数：env.sh 原有 ────────────────────────────────────────────────
step_install_system_libs() {
  local priv=(); [[ "$(id -u)" -ne 0 ]] && priv=(sudo)
  "${priv[@]}" apt update
  "${priv[@]}" apt install -y libglu1-mesa libgl1 libegl1 libxrandr2 libxinerama1 libxcursor1 libxi6 libxext6 libx11-6
}
step_set_glx_vendor()        { export __GLX_VENDOR_LIBRARY_NAME=nvidia; style_ok "已设置 __GLX_VENDOR_LIBRARY_NAME=nvidia"; }
step_uv_sync()               { ensure_project_root; require_cmd uv; uv sync; }
step_clone_isaaclab() {
  ensure_project_root; mkdir -p "$ROOT_DIR/third_party"
  if [[ -d "$ROOT_DIR/third_party/IsaacLab/.git" ]]; then style_dim "IsaacLab 已存在，跳过 clone"; return 0; fi
  git clone https://github.com/lehome-official/IsaacLab.git "$ROOT_DIR/third_party/IsaacLab"
}
step_install_isaaclab() {
  ensure_project_root; activate_venv
  [[ -x "$ROOT_DIR/third_party/IsaacLab/isaaclab.sh" ]] || { style_err "未找到 isaaclab.sh"; return 1; }
  "$ROOT_DIR/third_party/IsaacLab/isaaclab.sh" -i none
}
step_install_lehome_pkg()        { ensure_project_root; activate_venv; require_cmd uv; uv pip install -e "$ROOT_DIR/source/lehome"; }
step_download_assets()           { ensure_project_root; activate_venv; require_cmd hf; hf download lehome/asset_challenge --repo-type dataset --local-dir "$ROOT_DIR/Assets"; }
step_download_example_dataset()  { ensure_project_root; activate_venv; require_cmd hf; hf download lehome/dataset_challenge_merged --repo-type dataset --local-dir "$ROOT_DIR/Datasets/example"; }
step_install_uv_if_missing() {
  command -v uv >/dev/null 2>&1 && { style_dim "uv 已存在，跳过安装"; return 0; }
  curl -LsSf https://astral.sh/uv/install.sh | sh; export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"; require_cmd uv
}
step_install_hf_cli()  { ensure_project_root; activate_venv; require_cmd uv; uv pip install "huggingface_hub[cli]"; }
step_link_uv_cache() {
  local target="/root/data/.uv_cache" link_path="$HOME/.cache/uv"
  mkdir -p "$target" "$HOME/.cache"
  if [[ -e "$link_path" || -L "$link_path" ]]; then
    ui_confirm "将重置 $link_path 并重建软链，确认继续？" 0 || return 1; rm -rf "$link_path"; fi
  ln -s "$target" "$link_path"
}
step_setup_isaacsim_symlink() {
  ensure_project_root; activate_venv
  python -c "import isaacsim" >/dev/null
  local pkg; pkg="$(python -c "import isaacsim, os; print(os.path.dirname(isaacsim.__file__))")"
  [[ -n "$pkg" ]] || return 1
  safe_symlink "$pkg" "$ROOT_DIR/third_party/IsaacLab/_isaac_sim"
}

choose_shell_shortcut_items() {
  if [[ "$ASSUME_YES" -eq 1 ]]; then
    printf '%s\n' path go train eval save diff
    return 0
  fi

  local options=(
    "path | 补充 PATH"
    "go | 快速进入项目环境"
    "train | 打开训练向导"
    "eval | 打开评估向导（带参数时回退 bash eval）"
    "save | 保存新版本"
    "diff | 生成 diff 日志"
  )
  local picked_lines
  picked_lines="$(ui_choose_many_lines "选择要写入 ~/.bashrc 的配置项" "${options[@]}")"
  [[ -z "$picked_lines" ]] && return 0

  local line
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    printf '%s\n' "${line%% | *}"
  done <<<"$picked_lines"
}

append_shell_shortcut_block() {
  local begin="$1"
  shift
  local selected=("$@")

  printf '%s\n' "$begin"
  local item
  for item in "${selected[@]}"; do
    case "$item" in
      path)
        printf '%s\n' 'export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"'
        ;;
      go)
        printf 'go() { cd "%s" && source .venv/bin/activate; }\n' "$ROOT_DIR"
        ;;
      train)
        printf 'train() { bash "%s/all.sh" --step train_guide; }\n' "$ROOT_DIR"
        ;;
      eval)
        printf '%s\n' 'eval() {'
        printf '  if [[ $# -eq 0 ]]; then\n'
        printf '    bash "%s/all.sh" --step eval_guide\n' "$ROOT_DIR"
        printf '%s\n' '  else'
        printf '%s\n' '    builtin eval "$@"'
        printf '%s\n' '  fi'
        printf '%s\n' '}'
        ;;
      save)
        printf '%s\n' 'save() {'
        printf '%s\n' '  local version="${1:-}"'
        printf '%s\n' '  if [[ -n "$version" ]]; then'
        printf '%s\n' '    shift'
        printf '    SAVE_VERSION="$version" SAVE_NOTE="$*" bash "%s/all.sh" --step save_version\n' "$ROOT_DIR"
        printf '%s\n' '  else'
        printf '    bash "%s/all.sh" --step save_version\n' "$ROOT_DIR"
        printf '%s\n' '  fi'
        printf '%s\n' '}'
        ;;
      diff)
        printf 'diff() { bash "%s/all.sh" --step diff; }\n' "$ROOT_DIR"
        ;;
    esac
  done
  printf '%s\n' '# --- End LeHome all.sh shortcuts ---'
}

step_write_shell_shortcuts() {
  [[ "$WRITE_BASHRC" -ne 1 ]] && { style_warn "未传 --write-bashrc，跳过写入 ~/.bashrc"; return 0; }
  local bashrc="$HOME/.bashrc"
  local begin="# --- LeHome all.sh shortcuts ---"
  local selected_raw
  selected_raw="$(choose_shell_shortcut_items || true)"
  [[ -n "$selected_raw" ]] || { style_warn "未选择任何配置项，跳过写入 ~/.bashrc"; return 0; }
  local selected=()
  while IFS= read -r item; do
    [[ -n "$item" ]] && selected+=("$item")
  done <<<"$selected_raw"

  touch "$bashrc"; backup_file "$bashrc"
  awk \
    -v old_begin1="# --- LeHome 环境配置 ---" \
    -v old_end1="# --- End LeHome ---" \
    -v old_begin2="# --- LeHome env v3 ---" \
    -v old_end2="# --- End LeHome env v3 ---" \
    -v new_begin="$begin" \
    -v new_end="# --- End LeHome all.sh shortcuts ---" '
      $0==old_begin1 || $0==old_begin2 || $0==new_begin {skip=1; next}
      skip && ($0==old_end1 || $0==old_end2 || $0==new_end) {skip=0; next}
      !skip {print}
    ' "$bashrc" >"$bashrc.tmp"
  append_shell_shortcut_block "$begin" "${selected[@]}" >>"$bashrc.tmp"
  mv "$bashrc.tmp" "$bashrc"
  style_ok "已写入 ~/.bashrc（已备份）: ${selected[*]}"
}

# ── Step 处理函数：v1/prepare.sh ─────────────────────────────────────────────
step_prepare_full() {
  local install_libs=0
  [[ "${PREPARE_INSTALL_SYSTEM_LIBS:-0}" == "1" ]] && install_libs=1
  section "准备环境"; kv "Project root" "$ROOT_DIR"; kv "Install libs" "$install_libs"
  ensure_project_root; ensure_uv; link_uv_cache
  if [[ $install_libs -eq 1 ]]; then install_system_libs
  else warn "⚠️ 未安装系统图形库；若后续 IsaacSim/FFmpeg 报错，请设置 PREPARE_INSTALL_SYSTEM_LIBS=1 重新执行"; fi
  section "同步 Python 依赖"; cmd_preview 'uv sync --locked'; uv sync --locked; ok "✅ uv sync --locked 完成"
  section "安装 IsaacLab / LeHome"; clone_isaaclab_if_missing; activate_venv
  cmd_preview './third_party/IsaacLab/isaaclab.sh -i none'; ./third_party/IsaacLab/isaaclab.sh -i none
  cmd_preview 'uv pip install -e ./source/lehome'; uv pip install -e ./source/lehome
  cmd_preview 'uv pip install "huggingface_hub[cli]"'; uv pip install "huggingface_hub[cli]"
  section "校验核心导入"
  check_imports torch torchvision lerobot isaacsim lehome isaaclab isaaclab_tasks isaaclab_rl isaaclab_mimic isaaclab_assets isaaclab_contrib
  ok "✅ 核心环境安装完成"
  section "收尾配置"
  warn "⚠️ 即将触发 IsaacSim EULA；若终端提示接受协议，请按提示输入 Yes。"
  python -c "import isaacsim; print('IsaacSim import ok')"
  local isaacsim_path; isaacsim_path="$(python -c "import isaacsim, os; print(os.path.dirname(isaacsim.__file__))")"
  [[ -n "$isaacsim_path" ]] || die "❌ 无法解析 isaacsim 安装路径"
  safe_symlink "$isaacsim_path" "$ROOT_DIR/third_party/IsaacLab/_isaac_sim"
  ok "✅ 环境准备完成；请手动执行一次: source ~/.bashrc"
}

# ── Step 处理函数：v1/data.sh ────────────────────────────────────────────────
step_data_download() {
  local with_full=0; [[ "${DATA_WITH_FULL_DATASET:-0}" == "1" ]] && with_full=1
  section "下载数据资源"; kv "Project root" "$ROOT_DIR"; kv "Full dataset" "$with_full"
  ensure_project_root; activate_venv
  command -v hf >/dev/null 2>&1 || die "❌ 未找到 hf 命令，请先执行 prepare 步骤"
  cmd_preview 'hf download lehome/asset_challenge --repo-type dataset --local-dir Assets'
  hf download lehome/asset_challenge --repo-type dataset --local-dir Assets
  cmd_preview 'hf download lehome/dataset_challenge_merged --repo-type dataset --local-dir Datasets/example'
  hf download lehome/dataset_challenge_merged --repo-type dataset --local-dir Datasets/example
  if [[ $with_full -eq 1 ]]; then
    cmd_preview 'hf download lehome/dataset_challenge --repo-type dataset --local-dir Datasets/example'
    hf download lehome/dataset_challenge --repo-type dataset --local-dir Datasets/example
  else warn "⚠️ 未下载完整 dataset_challenge；如需 depth 信息，请设置 DATA_WITH_FULL_DATASET=1"; fi
  ok "✅ 数据下载完成"
}

# ── Step 处理函数：v1/eval.sh ────────────────────────────────────────────────
step_eval() {
  local model="${EVAL_MODEL:-xvla}"
  local default_run_dir
  case "$model" in
    act)      default_run_dir="outputs/train/act_top_long";;
    diffusion|dp) model="diffusion"; default_run_dir="outputs/train/dp_top_long";;
    smolvla)  default_run_dir="outputs/train/smolvla_top_long";;
    xvla)     default_run_dir="outputs/train/top_long/xvla_base_3w_steps";;
    *) die "❌ 不支持的模型: $model（可选: act / diffusion / smolvla / xvla）";;
  esac
  local policy_path="${EVAL_POLICY_PATH:-${default_run_dir}/checkpoints/last/pretrained_model}"
  local garment="${EVAL_GARMENT:-top_long}"
  local episodes="${EVAL_EPISODES:-5}"
  local dataset_root="${EVAL_DATASET_ROOT:-Datasets/example/${garment}_merged}"
  local log_name; log_name="$(date +'%m-%d-%H:%M')_${model}_eval_${garment}_ep${episodes}.log"

  ensure_project_root; activate_venv
  if ! command -v xvfb-run >/dev/null 2>&1; then die "❌ 未找到 xvfb-run，请先安装"; fi

  section "启动评估"; kv "Model" "$model"; kv "Policy path" "$policy_path"
  kv "Dataset root" "$dataset_root"; kv "Log file" "logs/$log_name"
  [[ -d "$dataset_root" ]] || warn "⚠️ dataset_root 目录不存在: $dataset_root"
  [[ -d "$policy_path"  ]] || warn "⚠️ policy_path 目录不存在: $policy_path"

  local extra_args=(--headless)
  [[ "$model" == "smolvla" ]] && extra_args+=(--task_description "fold the garment on the table")

  set +e
  exec xvfb-run -a env LEHOME_EVAL_XVFB_WRAPPED=1 \
    python -m scripts.eval \
      --policy_type lerobot \
      --policy_path "$policy_path" \
      --dataset_root "$dataset_root" \
      --garment_type "$garment" \
      --num_episodes "$episodes" \
      --enable_cameras \
      --device cpu \
      "${extra_args[@]}" \
    2>&1 | tee "$LOG_DIR/$log_name"
  local exit_code=${PIPESTATUS[0]}; set -e
  [[ $exit_code -eq 0 ]] && ok "✅ 评估完成: logs/$log_name" || die "❌ 评估失败，退出码: $exit_code"
}

# ── Step 处理函数：v1/xvla.sh ────────────────────────────────────────────────
# WandB 配置变量（可通过环境变量覆盖）
WANDB_PROJECT="${WANDB_PROJECT:-lehome}"
WANDB_ENTITY="${WANDB_ENTITY:-}"
WANDB_NOTES="${WANDB_NOTES:-}"
WANDB_RUN_ID="${WANDB_RUN_ID:-}"
WANDB_MODE="${WANDB_MODE:-online}"
WANDB_DISABLE_ARTIFACT="${WANDB_DISABLE_ARTIFACT:-false}"
WANDB_ENABLE="${WANDB_ENABLE:-false}"

normalize_bool() {
  local val="${1,,}" name="${2:-value}"
  case "$val" in true|1|yes|on) echo "true";; false|0|no|off|"") echo "false";;
    *) warn "⚠️ $name 值 '$1' 无法识别，默认 false"; echo "false";; esac
}

step_train_xvla() {
  ensure_train_xvla_yaml
  ensure_project_root; activate_venv
  local config_template="$ROOT_DIR/configs/train_xvla.yaml"
  [[ -f "$config_template" ]] || die "❌ 找不到 X-VLA 配置模板: $config_template"

  local dataset_repo dataset_root model_repo pretrained_path output_dir train_steps
  dataset_repo="$(python -c "import yaml,sys; d=yaml.safe_load(open(sys.argv[1])); print(d['dataset']['repo_id'])" "$config_template")"
  dataset_root="$(python -c "import yaml,sys; d=yaml.safe_load(open(sys.argv[1])); print(d['dataset']['root'])" "$config_template")"
  model_repo="$(python -c "import yaml,sys; d=yaml.safe_load(open(sys.argv[1])); print(d['policy']['repo_id'])" "$config_template")"
  pretrained_path="$(python -c "import yaml,sys; d=yaml.safe_load(open(sys.argv[1])); print(d['policy']['pretrained_path'])" "$config_template")"
  output_dir="$(python -c "import yaml,sys; d=yaml.safe_load(open(sys.argv[1])); print(d['output_dir'])" "$config_template")"
  train_steps="$(python -c "import yaml,sys; d=yaml.safe_load(open(sys.argv[1])); print(d['steps'])" "$config_template")"

  dataset_repo="${XVLA_DATASET_REPO:-$dataset_repo}"
  dataset_root="${XVLA_DATASET_ROOT:-$dataset_root}"
  model_repo="${XVLA_MODEL_REPO:-$model_repo}"
  pretrained_path="${XVLA_PRETRAINED_PATH:-$pretrained_path}"
  output_dir="${XVLA_OUTPUT_DIR:-$output_dir}"
  train_steps="${XVLA_TRAIN_STEPS:-$train_steps}"

  local job_name="${XVLA_JOB_NAME:-$(basename -- "$output_dir")}"
  [[ -z "$job_name" || "$job_name" == "." ]] && job_name="xvla_$(date +'%Y%m%d_%H%M%S')"
  local wandb_enabled; wandb_enabled="$(normalize_bool "$WANDB_ENABLE" "WANDB_ENABLE")"
  local dry_run; dry_run="$(normalize_bool "${XVLA_DRY_RUN:-false}" "XVLA_DRY_RUN")"

  local tmp_config; tmp_config="$(mktemp /tmp/train_xvla_XXXX.yaml)"
  [[ "$dry_run" != "true" ]] && trap 'rm -f "$tmp_config"' EXIT

  XVLA_CONFIG_TEMPLATE="$config_template" XVLA_TMP_CONFIG="$tmp_config" \
  XVLA_DATASET_REPO="$dataset_repo" XVLA_DATASET_ROOT="$dataset_root" \
  XVLA_MODEL_REPO="$model_repo" XVLA_PRETRAINED_PATH="$pretrained_path" \
  XVLA_OUTPUT_DIR="$output_dir" XVLA_TRAIN_STEPS="$train_steps" \
  XVLA_JOB_NAME="$job_name" XVLA_WANDB_ENABLE="$wandb_enabled" \
  XVLA_WANDB_PROJECT="$WANDB_PROJECT" XVLA_WANDB_ENTITY="$WANDB_ENTITY" \
  XVLA_WANDB_NOTES="$WANDB_NOTES" XVLA_WANDB_RUN_ID="$WANDB_RUN_ID" \
  XVLA_WANDB_MODE="$WANDB_MODE" XVLA_WANDB_DISABLE_ARTIFACT="$WANDB_DISABLE_ARTIFACT" \
  python - <<'PY'
import os, yaml
def maybe_none(v): return v if v else None
src, dst = os.environ["XVLA_CONFIG_TEMPLATE"], os.environ["XVLA_TMP_CONFIG"]
with open(src, 'r', encoding='utf-8') as f: data = yaml.safe_load(f)
data['dataset']['repo_id'] = os.environ['XVLA_DATASET_REPO']
data['dataset']['root']    = os.environ['XVLA_DATASET_ROOT']
data['policy']['repo_id']  = os.environ['XVLA_MODEL_REPO']
data['policy']['pretrained_path'] = os.environ['XVLA_PRETRAINED_PATH']
data['output_dir'] = os.environ['XVLA_OUTPUT_DIR']
data['steps']      = int(os.environ['XVLA_TRAIN_STEPS'])
data['job_name']   = os.environ['XVLA_JOB_NAME']
w = data.setdefault('wandb', {})
w['enable']           = os.environ['XVLA_WANDB_ENABLE'].lower() == 'true'
w['project']          = os.environ['XVLA_WANDB_PROJECT']
w['entity']           = maybe_none(os.environ['XVLA_WANDB_ENTITY'])
w['notes']            = maybe_none(os.environ['XVLA_WANDB_NOTES'])
w['run_id']           = maybe_none(os.environ['XVLA_WANDB_RUN_ID'])
w['mode']             = os.environ['XVLA_WANDB_MODE']
w['disable_artifact'] = os.environ['XVLA_WANDB_DISABLE_ARTIFACT'].lower() == 'true'
with open(dst, 'w', encoding='utf-8') as f: yaml.safe_dump(data, f, sort_keys=False, allow_unicode=True)
PY

  log "🔥 正在启动 X-VLA 训练..."; log "📄 临时配置: $tmp_config"
  log "📦 数据集: $dataset_repo  📁 路径: $dataset_root"
  log "🗂️ 输出: $output_dir  ⏱️ 步数: $train_steps"
  if [[ "$dry_run" == "true" ]]; then
    log "🧪 DRY_RUN 已开启，未真正启动训练。"; log "🧾 最终命令: lerobot-train --config_path=$tmp_config"; return 0; fi
  lerobot-train --config_path="$tmp_config"
}

step_eval_xvla() {
  ensure_train_xvla_yaml
  ensure_project_root; activate_venv
  local config_template="$ROOT_DIR/configs/train_xvla.yaml"
  local output_dir; output_dir="$(python -c "import yaml,sys; d=yaml.safe_load(open(sys.argv[1])); print(d['output_dir'])" "$config_template")"
  local eval_policy_path="${XVLA_EVAL_POLICY_PATH:-${output_dir}/checkpoints/last/pretrained_model}"
  local dataset_root="${XVLA_DATASET_ROOT:-$(python -c "import yaml,sys; d=yaml.safe_load(open(sys.argv[1])); print(d['dataset']['root'])" "$config_template")}"
  local garment="${EVAL_GARMENT:-top_long}"
  local episodes="${EVAL_EPISODES:-5}"
  local task_desc="${EVAL_TASK_DESCRIPTION:-fold the garment on the table}"

  command -v xvfb-run >/dev/null 2>&1 || die "❌ 未找到 xvfb-run"
  [[ -d "$eval_policy_path" ]] || die "❌ 评估模型路径不存在: $eval_policy_path"
  log "🧪 正在启动 X-VLA 评估..."; log "📦 模型路径: $eval_policy_path"; log "📚 数据路径: $dataset_root"
  xvfb-run -a python -m scripts.eval \
    --policy_type lerobot --policy_path "$eval_policy_path" \
    --dataset_root "$dataset_root" --garment_type "$garment" \
    --num_episodes "$episodes" --task_description "$task_desc" \
    --enable_cameras --device cpu --headless
}

# ── Step 处理函数：v1/versioning.sh ─────────────────────────────────────────
DEFAULT_GITHUB_USER="sudo-yf"
DEFAULT_GITHUB_EMAIL="$DEFAULT_GITHUB_USER@users.noreply.github.com"
VERSIONS_FILE="$ROOT_DIR/VERSIONS.md"

normalize_version_tag() {
  local raw="${1:-}"; [[ -n "$raw" ]] || die "❌ 版本号不能为空。"
  [[ "$raw" == v* ]] && printf '%s\n' "$raw" || printf 'v%s\n' "$raw"
}

configure_git_identity() {
  section "检查 Git 身份"
  if [[ -z "$(git config user.name || true)" ]]; then
    git config --global user.name "$DEFAULT_GITHUB_USER"
    git config --global user.email "$DEFAULT_GITHUB_EMAIL"
    ok "✅ 已设置 Git 身份: $DEFAULT_GITHUB_USER"
  else ok "✅ 当前 Git 身份: $(git config user.name)"; fi
}

ensure_personal_origin() {
  section "检查仓库远端"
  local main_origin; main_origin="$(git remote get-url origin 2>/dev/null || echo '')"
  if [[ "$main_origin" == *"lehome-official"* ]]; then
    warn "⚠️ 发现 origin 仍指向官方仓库，自动切换到个人仓库。"
    git remote set-url origin "https://github.com/$DEFAULT_GITHUB_USER/lehome-challenge.git"
    git remote add upstream "https://github.com/lehome-official/lehome-challenge.git" 2>/dev/null || true; fi
  ok "✅ origin: $(git remote get-url origin 2>/dev/null || echo '<missing>')"
}

step_git_basic_setup() {
  ensure_repo_root
  configure_git_identity
  ensure_personal_origin
}

collect_tag_rows() {
  git for-each-ref refs/tags --sort=-creatordate --format='%(refname:short)|%(creatordate:short)|%(objectname:short)|%(subject)'
}

render_versions_file() {
  local pending_tag="${1:-}" pending_date="${2:-}" pending_commit="${3:-}" pending_note="${4:-}"
  { echo "# Versions"; echo
    printf '%s\n' '本文件记录通过 `save` 流程创建的版本标签，便于快速检索。'; echo
    echo "| Version | Date | Commit | Notes |"; echo "| --- | --- | --- | --- |"
    [[ -n "$pending_tag" ]] && printf '| `%s` | `%s` | `%s` | %s |\n' "$pending_tag" "$pending_date" "$pending_commit" "${pending_note//|/ /}"
    collect_tag_rows | while IFS='|' read -r tag date commit subject; do
      [[ -n "$tag" ]] || continue
      [[ -n "$pending_tag" && "$tag" == "$pending_tag" ]] && continue
      printf '| `%s` | `%s` | `%s` | %s |\n' "$tag" "$date" "$commit" "${subject//|/ /}"; done
  } > "$VERSIONS_FILE"
}

show_versions() { ensure_repo_root; render_versions_file; section "版本索引"; cat "$VERSIONS_FILE"; }

save_version() {
  ensure_repo_root; ensure_path
  local version_arg="" note="" force_tag=false local_only=false
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --note) shift; [[ $# -gt 0 ]] || die "❌ --note 需要一个备注字符串。"; note="$1";;
      --force-tag) force_tag=true;;
      --local-only) local_only=true;;
      -h|--help) cat <<'USAGE'
Usage: save_version <version> [--note "备注"] [--force-tag] [--local-only]
USAGE
        return 0;;
      *) if [[ -z "$version_arg" ]]; then version_arg="$1"
         else [[ -n "$note" ]] && note+=" "; note+="$1"; fi;;
    esac; shift; done
  [[ -n "$version_arg" ]] || die "❌ 忘记写版本号啦！例如: save_version 3 xvla-wandb"
  local tag; tag="$(normalize_version_tag "$version_arg")"
  local today="$(date +%Y-%m-%d)" tag_subject="${note:-Auto save $tag}"
  local commit_msg="save: $tag"; [[ -n "$note" ]] && commit_msg+=" - $note"
  section "准备保存版本"; kv "Tag" "$tag"; kv "Note" "${note:-<none>}"
  kv "Local only" "$local_only"; kv "Force tag" "$force_tag"
  if git rev-parse "$tag" >/dev/null 2>&1; then
    [[ "$force_tag" != true ]] && die "❌ 标签 $tag 已存在。如需覆盖，请传 --force-tag。"
    warn "⚠️ 标签 $tag 已存在，将按要求覆盖。"; fi
  activate_venv || true; configure_git_identity; ensure_personal_origin
  section "提交当前工作区"; git add -A
  if git diff --cached --quiet; then
    warn "⚠️ 当前没有未提交改动，将创建一个空的版本提交。"; git commit --allow-empty -m "$commit_msg"
  else git commit -m "$commit_msg"; fi
  local commit_short; commit_short="$(git rev-parse --short HEAD)"
  section "写入版本标签"
  [[ "$force_tag" == true ]] && { git tag -d "$tag" >/dev/null 2>&1 || true; }
  git tag -a "$tag" -m "$tag_subject"; ok "✅ 已创建标签: $tag"
  section "刷新版本索引"; render_versions_file "$tag" "$today" "$commit_short" "$tag_subject"
  git add "$VERSIONS_FILE"
  if git diff --cached --quiet; then warn "⚠️ VERSIONS.md 无变化，跳过索引提交。"
  else git commit -m "docs: refresh version index for $tag" >/dev/null; ok "✅ 已更新版本索引提交"; fi
  if [[ "$local_only" != true ]]; then
    section "推送远端"; local branch; branch="$(git rev-parse --abbrev-ref HEAD)"
    cmd_preview "git push origin $branch"; git push origin "$branch"
    [[ "$force_tag" == true ]] && { git push origin ":refs/tags/$tag" >/dev/null 2>&1 || true; }
    cmd_preview "git push origin $tag"; git push origin "$tag"; ok "✅ 已推送分支与标签"
  else warn "⚠️ 已跳过远端推送（--local-only）"; fi
  section "版本保存完成"; kv "Tag" "$tag"; kv "Tagged commit" "$commit_short"; kv "Index" "$VERSIONS_FILE"
}

step_save_version() {
  local version="${SAVE_VERSION:-}"
  [[ -n "$version" ]] || { read -r -p "请输入版本号: " version; }
  local note="${SAVE_NOTE:-}"
  save_version "$version" ${note:+--note "$note"}
}

# ── Step 处理函数：v1/step_git.sh ────────────────────────────────────────────
step_git_save() {
  local version="${SAVE_VERSION:-}"
  [[ -n "$version" ]] || { read -r -p "请输入版本号: " version; }
  [[ -n "$version" ]] || die "❌ 错误: 忘记写版本号啦！"
  local target_dir="$ROOT_DIR" github_user="${DEFAULT_GITHUB_USER:-sudo-yf}"
  local github_email="${DEFAULT_GITHUB_EMAIL:-$github_user@users.noreply.github.com}"
  local ver="v$version" commit_msg="Auto save version v$version"
  echo "=================================================="; echo "🛡️  开始防夺舍检测与一键备份 (目标版本: v$version)"
  echo "=================================================="; cd "$target_dir"
  [[ -f ".venv/bin/activate" ]] && { source .venv/bin/activate; echo "✅ 虚拟环境已激活"; } || echo "⚠️ 警告: 未找到 .venv，将使用系统环境继续"
  echo "👤 [1/5] 检查 Git 身份配置..."
  if [[ -z "$(git config user.name)" ]]; then
    git config --global user.name "$github_user"; git config --global user.email "$github_email"
    echo "✅ 身份已设为: $github_user"
  else echo "✅ 身份已确认: $(git config user.name)"; fi
  echo "🔍 [2/5] 检查仓库归属..."
  local main_origin; main_origin="$(git remote get-url origin 2>/dev/null || echo '')"
  if [[ "$main_origin" == *"lehome-official"* ]]; then
    echo "⚠️ 发现仓库被官方占用，正在为你执行换源..."
    git remote set-url origin "https://github.com/$github_user/lehome-challenge.git"
    git remote add upstream "https://github.com/lehome-official/lehome-challenge.git" 2>/dev/null || true
  else echo "✅ 仓库归属正常"; fi
  echo "🚀 [3/5] 处理代码变动..."; git add .
  git commit -m "$commit_msg" || echo "💤 工作区无新变动，跳过 commit 阶段..."
  echo "🏷️  [4/5] 更新版本标签..."
  git tag -d "$ver" 2>/dev/null || true; git tag "$ver"
  echo "📤 [5/5] 推送到 GitHub ($github_user)..."
  local current_branch; current_branch="$(git rev-parse --abbrev-ref HEAD)"
  git push origin "$current_branch"; git push origin "$ver" -f
  echo "=================================================="; echo "🎉 完美收工！$ver 已包含最新环境状态并同步！"
}

# ── Step 处理函数：v1/step_vpn.sh ────────────────────────────────────────────
step_vpn_setup() {
  echo -e "\033[0;35m==================================================\033[0m"
  echo -e "\033[0;35m🌐  Clash-for-Linux 自动化部署工具\033[0m"
  echo -e "\033[0;35m==================================================\033[0m"
  if [[ -f "/public/bin/network_accelerate" ]]; then
    source /public/bin/network_accelerate; echo -e "\033[0;32m✅ 加速已开启\033[0m"
  else echo -e "\033[1;33m⚠️  未找到加速脚本，将尝试普通连接。\033[0m"; fi
  rm -rf clash-for-linux-install
  git clone --branch master --depth 1 https://github.com/nelvko/clash-for-linux-install.git
  [[ -d "clash-for-linux-install" ]] || die "❌ 仓库拉取失败，请检查网络连接！"
  cd clash-for-linux-install
  sed -i 's|https://gh-proxy.org||g' install.sh 2>/dev/null || true
  cat <<EOF > .env
KERNEL_NAME=mihomo
CLASH_BASE_DIR=~/clashctl
CLASH_CONFIG_URL=${CLASH_CONFIG_URL:-}
CLASH_SUB_UA=clash-verge/v2.4.0
VERSION_MIHOMO=v1.19.17
VERSION_YQ=v4.49.2
VERSION_SUBCONVERTER=v0.9.0
URL_CLASH_UI=http://board.zash.run.place
ZIP_UI=resources/zip/dist.zip
URL_GH_PROXY=
EOF
  bash install.sh
  if [[ -f "/public/bin/network_accelerate_stop" ]]; then source /public/bin/network_accelerate_stop; fi
  echo -e "\033[0;32m🎉 代理部署大功告成！\033[0m"
}

# ── Step 处理函数：v1/ai.sh ──────────────────────────────────────────────────
step_ai_tools() {
  echo -e "\033[0;32m=== 🚀 开始全自动配置 AI 编程环境 ===\033[0m"
  if ! command -v node &>/dev/null; then
    if command -v conda &>/dev/null; then conda install -c conda-forge nodejs=20 -y
    else die "错误: 未检测到 Conda 环境。请先安装 Conda。"; fi
  else echo -e "Node.js 已安装: \033[0;32m$(node -v)\033[0m"; fi
  npm config set registry https://registry.npmmirror.com
  npm install -g @anthropic-ai/claude-code @openai/codex zcf happy-coder
  echo -e "\033[0;32mAI 工具链安装完成！\033[0m"
}

step_train_guide() {
  ensure_train_xvla_yaml
  ensure_project_root
  local python_bin="$ROOT_DIR/.venv/bin/python"
  local train_bin="$ROOT_DIR/.venv/bin/lerobot-train"
  [[ -x "$python_bin" ]] || die "❌ 未找到 $python_bin，请先完成环境准备。"
  [[ -x "$train_bin" ]] || die "❌ 未找到 $train_bin，请先完成环境准备。"

  echo "================================================"
  echo "  LeHome 训练参数配置向导"
  echo "  直接按 Enter 使用默认值"
  echo "================================================"
  echo ""

  wizard_section "基础配置"
  echo "  可用配置: train_xvla.yaml / train_act.yaml / train_dp.yaml / train_smolvla.yaml"
  local base_config
  local base_config_default="${TRAIN_BASE_CONFIG:-configs/train_xvla.yaml}"
  wizard_prompt_value "Base config" "$base_config_default" "$base_config_default" base_config
  [[ -f "$ROOT_DIR/$base_config" || -f "$base_config" ]] || die "❌ 配置文件不存在: $base_config"
  [[ -f "$ROOT_DIR/$base_config" ]] && base_config="$ROOT_DIR/$base_config"

  wizard_section "训练超参数"
  local default_output="${XVLA_OUTPUT_DIR:-outputs/train/xvla_$(date +%m%d)}"
  local output_dir dataset_root steps batch_size save_freq log_freq
  wizard_prompt_value "Output dir" "$default_output" "$default_output" output_dir
  local dataset_default="${XVLA_DATASET_ROOT:-${EVAL_DATASET_ROOT:-Datasets/example/top_long_merged}}"
  wizard_prompt_value "Dataset path" "$dataset_default" "$dataset_default" dataset_root
  wizard_prompt_value "Steps" "30000" "30000" steps
  wizard_prompt_value "Batch size" "8" "8" batch_size
  wizard_prompt_value "Save freq" "5000" "5000" save_freq
  wizard_prompt_value "Log freq" "1000" "1000" log_freq

  wizard_section "WandB 配置"
  local wandb_enable wandb_project="" wandb_entity=""
  wizard_prompt_value "Enable WandB" "n/Y" "n" wandb_enable
  if [[ "$wandb_enable" =~ ^[Yy] ]]; then
    wizard_prompt_value "WandB project" "lehome_xvla" "lehome_xvla" wandb_project
    wizard_prompt_optional "WandB entity" "leave empty" wandb_entity
  fi

  local timestamp gen_config
  timestamp="$(date +%m%d_%H%M%S)"
  gen_config="$ROOT_DIR/configs/train_generated_${timestamp}.yaml"

  echo
  echo "正在生成配置文件..."
  "$python_bin" - <<PYEOF
import yaml

with open(r"$base_config", "r", encoding="utf-8") as f:
    cfg = yaml.safe_load(f)

cfg["output_dir"] = r"$output_dir"
cfg["steps"] = int("$steps")
cfg["batch_size"] = int("$batch_size")
cfg["save_freq"] = int("$save_freq")
cfg["log_freq"] = int("$log_freq")

cfg.setdefault("dataset", {})
cfg["dataset"]["root"] = r"$dataset_root"

cfg.setdefault("wandb", {})
wandb_on = "$wandb_enable".lower().startswith("y")
cfg["wandb"]["enable"] = wandb_on
if wandb_on:
    cfg["wandb"]["project"] = r"$wandb_project"
    if r"$wandb_entity":
        cfg["wandb"]["entity"] = r"$wandb_entity"
    cfg["wandb"]["mode"] = "online"
else:
    cfg["wandb"]["mode"] = "disabled"

with open(r"$gen_config", "w", encoding="utf-8") as f:
    yaml.safe_dump(cfg, f, sort_keys=False, allow_unicode=True)
PYEOF

  local cmd log_file
  cmd="$train_bin --config_path=$gen_config"
  log_file="$ROOT_DIR/logs/$(date +%m-%d_%H-%M-%S)_train_${steps}steps.log"

  echo
  echo "================================================"
  echo "  生成的配置: ${gen_config#$ROOT_DIR/}"
  echo "  关键信息："
  printf "  %-16s ${WHITE}%s${NC}\n" "Dataset path:" "$dataset_root"
  printf "  %-16s ${WHITE}%s${NC}\n" "Output dir:" "$output_dir"
  printf "  %-16s ${WHITE}%s${NC}\n" "Steps:" "$steps"
  echo "------------------------------------------------"
  echo "  最终命令："
  echo "------------------------------------------------"
  echo "  cd $ROOT_DIR && \\"
  echo "  nohup $cmd \\"
  echo "    > ${log_file#$ROOT_DIR/} 2>&1 &"
  echo "  echo \"训练已启动，PID: \$!\""
  echo "================================================"
  echo ""

  local run_now
  wizard_prompt_value "Run now" "y/N" "N" run_now
  if [[ "$run_now" =~ ^[Yy] ]]; then
    mkdir -p "$ROOT_DIR/logs"
    (
      cd "$ROOT_DIR"
      nohup "$train_bin" --config_path="$gen_config" >"$log_file" 2>&1 &
      echo "训练已启动，PID: $!"
      echo "日志文件: ${log_file#$ROOT_DIR/}"
      echo "查看日志: tail -f ${log_file#$ROOT_DIR/}"
    )
  else
    echo "未运行，请手动执行上方命令。"
  fi
}

step_eval_guide() {
  ensure_project_root
  local python_bin="$ROOT_DIR/.venv/bin/python"
  [[ -x "$python_bin" ]] || die "❌ 未找到 $python_bin，请先完成环境准备。"

  echo "================================================"
  echo "  LeHome 评估参数配置向导"
  echo "  直接按 Enter 使用默认值"
  echo "================================================"
  echo ""

  wizard_section "策略配置"
  local policy_type policy_path
  wizard_prompt_value "Policy type" "lerobot" "lerobot" policy_type
  local policy_default="${EVAL_POLICY_PATH:-${XVLA_EVAL_POLICY_PATH:-outputs/train/xvla_30k/checkpoints/last/pretrained_model}}"
  wizard_prompt_value "Policy path" "$policy_default" "$policy_default" policy_path

  wizard_section "衣物与数据"
  echo "  可选衣物: top_long / top_short / pant_long / pant_short / custom"
  local garment_type dataset_root
  wizard_prompt_value "Garment type" "top_long" "top_long" garment_type
  local dataset_default="${EVAL_DATASET_ROOT:-${XVLA_DATASET_ROOT:-Datasets/example/top_long_merged}}"
  wizard_prompt_value "Dataset path" "$dataset_default" "$dataset_default" dataset_root

  wizard_section "评估参数"
  local num_episodes device seed use_random_seed task_desc
  wizard_prompt_value "Episodes" "24" "24" num_episodes
  wizard_prompt_value "Device" "cpu" "cpu" device
  wizard_prompt_value "Seed" "42" "42" seed
  wizard_prompt_value "Random seed" "n/Y" "n" use_random_seed
  wizard_prompt_value "Task desc" "fold the garment on the table" "fold the garment on the table" task_desc

  wizard_section "运行模式"
  local headless enable_cameras
  wizard_prompt_value "Headless" "Y/n" "Y" headless
  wizard_prompt_value "Cameras" "Y/n" "Y" enable_cameras

  wizard_section "录制选项"
  local save_video video_dir="" save_datasets eval_dataset_path=""
  wizard_prompt_value "Save video" "n/Y" "n" save_video
  if [[ "$save_video" =~ ^[Yy] ]]; then
    wizard_prompt_value "Video dir" "outputs/eval_videos" "outputs/eval_videos" video_dir
  fi
  wizard_prompt_value "Save datasets" "n/Y" "n" save_datasets
  if [[ "$save_datasets" =~ ^[Yy] ]]; then
    wizard_prompt_value "Eval dataset" "Datasets/eval" "Datasets/eval" eval_dataset_path
  fi

  local cmd log_file
  cmd="$python_bin -u -m scripts.eval"
  cmd+=" --policy_type \"$policy_type\""
  cmd+=" --policy_path \"$policy_path\""
  cmd+=" --garment_type \"$garment_type\""
  cmd+=" --dataset_root \"$dataset_root\""
  cmd+=" --num_episodes $num_episodes"
  cmd+=" --device $device"
  cmd+=" --seed $seed"
  cmd+=" --task_description \"$task_desc\""
  [[ "$use_random_seed" =~ ^[Yy] ]] && cmd+=" --use_random_seed"
  [[ "$headless" =~ ^[Yy] ]] && cmd+=" --headless"
  [[ "$enable_cameras" =~ ^[Yy] ]] && cmd+=" --enable_cameras"
  [[ "$save_video" =~ ^[Yy] ]] && cmd+=" --save_video --video_dir \"$video_dir\""
  [[ "$save_datasets" =~ ^[Yy] ]] && cmd+=" --save_datasets --eval_dataset_path \"$eval_dataset_path\""

  log_file="$ROOT_DIR/logs/$(date +%m-%d_%H-%M-%S)_eval_${garment_type}_${num_episodes}eps.log"

  echo
  echo "================================================"
  echo "  关键信息："
  printf "  %-16s ${WHITE}%s${NC}\n" "Dataset path:" "$dataset_root"
  printf "  %-16s ${WHITE}%s${NC}\n" "Policy path:" "$policy_path"
  printf "  %-16s ${WHITE}%s${NC}\n" "Episodes:" "$num_episodes"
  echo "------------------------------------------------"
  echo "  最终命令："
  echo "------------------------------------------------"
  echo "  cd $ROOT_DIR && \\"
  echo "  nohup $cmd \\"
  echo "    > ${log_file#$ROOT_DIR/} 2>&1 &"
  echo "  echo \"评估已启动，PID: \$!\""
  echo "================================================"
  echo ""

  local run_now
  wizard_prompt_value "Run now" "y/N" "N" run_now
  if [[ "$run_now" =~ ^[Yy] ]]; then
    mkdir -p "$ROOT_DIR/logs"
    (
      cd "$ROOT_DIR"
      # shellcheck disable=SC2086
      eval "nohup $cmd > \"$log_file\" 2>&1 &"
      echo "评估已启动，PID: $!"
      echo "日志文件: ${log_file#$ROOT_DIR/}"
      echo "查看日志: tail -f ${log_file#$ROOT_DIR/}"
    )
  else
    echo "未运行，请手动执行上方命令。"
  fi
}

# ── Step 处理函数：diff.sh ───────────────────────────────────────────────────
step_diff() {
  local repo="$ROOT_DIR" log_file="$ROOT_DIR/diff.log" upstream="upstream/main"
  cd "$repo" || die "❌ 无法进入项目目录: $repo"
  if ! git remote | grep -q "^upstream$"; then
    git remote add upstream https://github.com/lehome-official/lehome-challenge.git; fi
  git fetch upstream --quiet
  { echo "生成时间: $(date '+%Y-%m-%d %H:%M:%S')"; echo ""
    echo "【M 修改】"; git diff "$upstream" HEAD --name-status | grep "^M" || echo "  (无)"; echo ""
    echo "【A 新增】"; git diff "$upstream" HEAD --name-status | grep "^A" || echo "  (无)"; echo ""
    echo "【D 删除】"; git diff "$upstream" HEAD --name-status | grep "^D" || echo "  (无)"; echo ""
    echo "【修改详情】"; echo "----------------------------------------"
    git diff "$upstream" HEAD --diff-filter=M -- scripts/ source/ | while IFS= read -r line; do
      if [[ "$line" =~ ^"diff --git" ]]; then echo ""; echo ">>> ${line#diff --git a/}"
      elif [[ "$line" =~ ^@@ ]]; then echo "$line"
      elif [[ "$line" =~ ^\+\+\+ ]] || [[ "$line" =~ ^"---" ]] || [[ "$line" =~ ^"index" ]]; then :
      elif [[ "$line" =~ ^\+ ]]; then echo "新增: ${line:1}"
      elif [[ "$line" =~ ^\- ]]; then echo "删除: ${line:1}"; fi; done
  } > "$log_file"
  ok "[done] $log_file"
}

# ── register_steps ────────────────────────────────────────────────────────────
register_steps() {
  # ── 官方安装步骤 (env.sh 原有) ──
  add_step "install_system_libs"       "安装系统图形依赖"         "official" "high"   "1" "step_install_system_libs"       "apt install -y libglu1-mesa libgl1 ..."                    "服务器环境依赖，来自 docs/installation.md"
  add_step "set_glx_vendor"            "设置 NVIDIA GLX 变量"     "official" "low"    "1" "step_set_glx_vendor"            "export __GLX_VENDOR_LIBRARY_NAME=nvidia"                   "来自 docs/installation.md"
  add_step "uv_sync"                   "同步 Python 依赖"         "official" "medium" "1" "step_uv_sync"                   "uv sync"                                                   "来自 docs/installation.md"
  add_step "clone_isaaclab"            "克隆 IsaacLab"            "official" "low"    "1" "step_clone_isaaclab"            "git clone .../IsaacLab.git third_party/IsaacLab"           "来自 docs/installation.md"
  add_step "install_isaaclab"          "安装 IsaacLab"            "official" "medium" "1" "step_install_isaaclab"          "source .venv/bin/activate && ./third_party/IsaacLab/isaaclab.sh -i none" "来自 docs/installation.md"
  add_step "install_lehome_pkg"        "安装 LeHome 包"           "official" "medium" "1" "step_install_lehome_pkg"        "uv pip install -e ./source/lehome"                         "来自 docs/installation.md"
  add_step "download_assets"           "下载仿真资产"             "official" "medium" "1" "step_download_assets"           "hf download lehome/asset_challenge ..."                    "来自 docs/readme.md"
  add_step "download_example_dataset"  "下载示例数据集"           "official" "medium" "1" "step_download_example_dataset"  "hf download lehome/dataset_challenge_merged ..."           "来自 docs/readme.md"
  # ── 增强安装步骤 (env.sh 原有) ──
  add_step "install_uv_if_missing"     "安装 uv（缺失时）"        "enhanced" "medium" "0" "step_install_uv_if_missing"     "curl -LsSf https://astral.sh/uv/install.sh | sh"           "非官方增强：自动安装 uv"
  add_step "install_hf_cli"            "安装 HuggingFace CLI"     "enhanced" "medium" "0" "step_install_hf_cli"            "uv pip install \"huggingface_hub[cli]\""                   "非官方增强：确保 hf 命令可用"
  add_step "link_uv_cache"             "配置 uv 缓存软链"         "enhanced" "high"   "0" "step_link_uv_cache"             "ln -sf /root/data/.uv_cache ~/.cache/uv"                   "非官方增强：迁移缓存到数据盘"
  add_step "setup_isaacsim_symlink"    "配置 IsaacSim 软链"       "enhanced" "medium" "0" "step_setup_isaacsim_symlink"    "python -c \"import isaacsim\" && ln -sf <path> _isaac_sim" "非官方增强：补齐 IsaacLab 与 IsaacSim 软链"
  add_step "write_shell_shortcuts"     "写入 shell 快捷配置"      "enhanced" "high"   "0" "step_write_shell_shortcuts"     "write ~/.bashrc block"                                     "非官方增强：仅在 --write-bashrc 时执行"
  # ── v1 新增步骤 ──
  add_step "prepare_full"              "完整环境准备（v1 流程）"  "enhanced" "high"   "0" "step_prepare_full"              "uv sync --locked && isaaclab.sh -i none && ..."            "v1/prepare.sh：完整安装流程含导入校验"
  add_step "data_download"             "下载数据资源（v1 流程）"  "enhanced" "medium" "0" "step_data_download"             "hf download assets + dataset_challenge_merged"             "v1/data.sh：下载资产与数据集，可选完整版"
  add_step "eval"                      "运行评估"                 "enhanced" "medium" "0" "step_eval"                      "xvfb-run python -m scripts.eval ..."                       "v1/eval.sh：支持 act/diffusion/smolvla/xvla"
  add_step "train_guide"               "交互式训练向导"           "enhanced" "medium" "0" "step_train_guide"               "内置训练向导"                                              "all.sh 内置：交互式训练参数配置向导"
  add_step "eval_guide"                "交互式评估向导"           "enhanced" "medium" "0" "step_eval_guide"                "内置评估向导"                                              "all.sh 内置：交互式评估参数配置向导"
  add_step "train_xvla"                "训练 X-VLA"               "enhanced" "high"   "0" "step_train_xvla"                "lerobot-train --config_path=<tmp_config>"                  "v1/xvla.sh：从 configs/train_xvla.yaml 生成临时配置并训练"
  add_step "eval_xvla"                 "评估 X-VLA"               "enhanced" "medium" "0" "step_eval_xvla"                 "xvfb-run python -m scripts.eval (xvla)"                    "v1/xvla.sh：评估 X-VLA checkpoint"
  add_step "git_basic_setup"           "Git 基础配置"             "enhanced" "medium" "0" "step_git_basic_setup"           "git config --global user.name ... && git remote set-url ..." "初始化 Git 身份并校正仓库远端"
  add_step "save_version"              "保存版本（versioning）"   "enhanced" "high"   "0" "step_save_version"              "git commit + tag + push"                                   "v1/versioning.sh：提交、打 tag、推送远端"
  add_step "git_save"                  "Git 快速保存（step_git）" "enhanced" "high"   "0" "step_git_save"                  "git add . && git commit && git tag && git push"            "v1/step_git.sh：一键备份到 GitHub"
  add_step "vpn_setup"                 "配置 VPN（Clash）"        "enhanced" "high"   "0" "step_vpn_setup"                 "git clone clash-for-linux-install && bash install.sh"      "v1/step_vpn.sh：部署 Clash 代理"
  add_step "ai_tools"                  "安装 AI 工具链"           "enhanced" "medium" "0" "step_ai_tools"                  "npm install -g claude-code codex zcf happy-coder"          "v1/ai.sh：安装 Claude Code / Codex / ZCF"
  add_step "diff"                      "生成 diff 日志"           "enhanced" "low"    "0" "step_diff"                      "git diff upstream/main HEAD > diff.log"                    "diff.sh：对比 upstream/main 生成变更报告"
}

# ── main_menu ─────────────────────────────────────────────────────────────────
main_menu() {
  while true; do
    local choice
    if [[ "$HAS_GUM" -eq 1 ]]; then
      choice="$(ui_choose_numbered_option "$(show_compact_main_menu_header)" \
        "1. 执行全流程（推荐）" \
        "2. 环境准备" \
        "3. 数据资源管理" \
        "4. X-VLA 工作台" \
        "5. AI 开发工具链" \
        "6. github配置与Shell 快捷命令" \
        "7. VPN 与代理配置" \
        "0. 退出")"
    else
      echo
      show_banner
      choice="$(ui_choose_numbered_option "" \
        "1. 执行全流程（推荐）" \
        "2. 环境准备" \
        "3. 数据资源管理" \
        "4. X-VLA 工作台" \
        "5. AI 开发工具链" \
        "6. github配置与Shell 快捷命令" \
        "7. VPN 与代理配置" \
        "0. 退出")"
    fi
    case "$choice" in
      1) run_module_full_flow || return 1 ;;
      2) run_module_environment_setup || return 1 ;;
      3) run_module_data_resources || return 1 ;;
      4) run_module_xvla_workspace || return 1 ;;
      5) run_module_ai_tools || return 1 ;;
      6) run_module_dev_tools || return 1 ;;
      7) run_module_vpn || return 1 ;;
      0|"") style_dim "退出。"; return 0 ;;
      *) style_warn "无效选项: $choice" ;;
    esac; done
}

# ── print_usage ───────────────────────────────────────────────────────────────
print_usage() {
  cat <<'USAGE'
Usage: bash all.sh [options]

Options:
  --mode confirm|auto     执行模式 (default: confirm)
  --yes, -y               自动模式，跳过确认
  --dry-run               仅打印步骤，不执行
  --list                  打印步骤列表并退出
  --step <step_id>        执行指定步骤（可重复）
  --write-bashrc          允许写入 ~/.bashrc
  --log-file <path>       自定义日志路径
  -h, --help              显示帮助

环境变量（控制各步骤行为）:
  PREPARE_INSTALL_SYSTEM_LIBS=1   prepare_full 步骤安装系统库
  DATA_WITH_FULL_DATASET=1        data_download 步骤下载完整数据集
  EVAL_MODEL=xvla                 eval 步骤使用的模型 (act/diffusion/smolvla/xvla)
  EVAL_GARMENT=top_long           评估衣物类型
  EVAL_EPISODES=5                 评估 episode 数量
  EVAL_POLICY_PATH=<path>         评估模型路径
  EVAL_DATASET_ROOT=<path>        评估数据集路径
  XVLA_DATASET_REPO=<repo>        X-VLA 训练数据集仓库
  XVLA_DATASET_ROOT=<path>        X-VLA 训练数据集路径
  XVLA_OUTPUT_DIR=<path>          X-VLA 训练输出目录
  XVLA_TRAIN_STEPS=<n>            X-VLA 训练步数
  XVLA_DRY_RUN=true               X-VLA 训练 dry-run 模式
  WANDB_ENABLE=true               启用 WandB
  WANDB_PROJECT=<project>         WandB 项目名
  SAVE_VERSION=<version>          保存版本号
  SAVE_NOTE=<note>                保存版本备注
  CLASH_CONFIG_URL=<url>          VPN 订阅链接
USAGE
}

# ── parse_args ────────────────────────────────────────────────────────────────
parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --mode) [[ $# -ge 2 ]] || { style_err "--mode 需要参数"; exit 1; }
        MODE="$2"; case "$MODE" in confirm|auto) ;; *) style_err "--mode 仅支持 confirm|auto"; exit 1;; esac; shift 2;;
      --yes|-y) ASSUME_YES=1; MODE="auto"; shift;;
      --dry-run) DRY_RUN=1; shift;;
      --list) LIST_ONLY=1; shift;;
      --step) [[ $# -ge 2 ]] || { style_err "--step 需要 step_id"; exit 1; }
        REQUESTED_STEP_IDS+=("$2"); shift 2;;
      --write-bashrc) WRITE_BASHRC=1; shift;;
      --log-file) [[ $# -ge 2 ]] || { style_err "--log-file 需要路径"; exit 1; }
        LOG_FILE="$2"; mkdir -p "$(dirname "$LOG_FILE")"; shift 2;;
      -h|--help) print_usage; exit 0;;
      *) style_err "不支持的参数: $1"; print_usage; exit 1;;
    esac; done
}

# ── main ──────────────────────────────────────────────────────────────────────
main() {
  command -v gum >/dev/null 2>&1 && HAS_GUM=1
  parse_args "$@"; register_steps
  log_line "启动 all.sh mode=$MODE dry_run=$DRY_RUN write_bashrc=$WRITE_BASHRC has_gum=$HAS_GUM"
  if [[ "$LIST_ONLY" -eq 1 ]]; then show_step_list_only; exit 0; fi
  if [[ ${#REQUESTED_STEP_IDS[@]} -gt 0 ]]; then
    local status=0
    run_steps_by_ids "${REQUESTED_STEP_IDS[@]}" || status=$?
    print_summary; exit "$status"; fi
  main_menu; print_summary
}

main "$@"
