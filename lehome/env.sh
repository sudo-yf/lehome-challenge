#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
LOG_DIR="$ROOT_DIR/logs"
mkdir -p "$LOG_DIR"

MODE="confirm"
ASSUME_YES=0
DRY_RUN=0
WRITE_BASHRC=0
LIST_ONLY=0
HAS_GUM=0
LOG_FILE="$LOG_DIR/interactive-step-runner-$(date +%Y%m%d-%H%M%S).log"

# Execution stats
SUCCESS_COUNT=0
SKIPPED_COUNT=0
FAILED_COUNT=0

# Requested steps from CLI
REQUESTED_STEP_IDS=()

# Step registry
STEP_IDS=()
STEP_TITLES=()
STEP_TYPES=()
STEP_RISKS=()
STEP_DEFAULTS=()
STEP_HANDLERS=()
STEP_COMMANDS=()
STEP_DESCS=()

export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"

log_line() {
  printf '[%s] %s\n' "$(date '+%F %T')" "$*" >>"$LOG_FILE"
}

print_usage() {
  cat <<'USAGE'
Usage: bash lehome/env.sh [options]

Options:
  --mode confirm|auto     Execution mode (default: confirm)
  --yes, -y               Run in auto mode and skip confirmations
  --dry-run               Print steps without executing
  --list                  Print step list and exit
  --step <step_id>        Run a specific step (can be repeated)
  --write-bashrc          Allow writing shell shortcuts to ~/.bashrc
  --log-file <path>       Custom log file path
  -h, --help              Show this help
USAGE
}

style_dim() {
  if [[ "$HAS_GUM" -eq 1 ]]; then
    gum style --foreground 245 "$*"
  else
    echo "$*"
  fi
}

style_ok() {
  if [[ "$HAS_GUM" -eq 1 ]]; then
    gum style --foreground 46 "$*"
  else
    echo "$*"
  fi
}

style_warn() {
  if [[ "$HAS_GUM" -eq 1 ]]; then
    gum style --foreground 214 "$*"
  else
    echo "$*"
  fi
}

style_err() {
  if [[ "$HAS_GUM" -eq 1 ]]; then
    gum style --foreground 196 "$*"
  else
    echo "$*" >&2
  fi
}

ui_confirm() {
  local prompt="$1"
  local default_yes="${2:-1}"

  if [[ "$ASSUME_YES" -eq 1 ]]; then
    return 0
  fi

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
    read -r -p "$prompt [Y/n]: " ans
    ans="${ans:-Y}"
  else
    read -r -p "$prompt [y/N]: " ans
    ans="${ans:-N}"
  fi

  case "${ans,,}" in
    y|yes) return 0 ;;
    *) return 1 ;;
  esac
}

ui_choose_one() {
  local header="$1"
  shift
  local options=("$@")

  if [[ "$HAS_GUM" -eq 1 ]]; then
    printf '%s\n' "${options[@]}" | gum choose --header "$header" || true
    return
  fi

  echo "$header"
  local i=1
  for opt in "${options[@]}"; do
    echo "  $i) $opt"
    i=$((i + 1))
  done
  local idx
  read -r -p "请输入序号: " idx
  if [[ "$idx" =~ ^[0-9]+$ ]] && ((idx >= 1 && idx <= ${#options[@]})); then
    echo "${options[$((idx - 1))]}"
  fi
}

ui_choose_many_lines() {
  local header="$1"
  shift
  local options=("$@")

  if [[ "$HAS_GUM" -eq 1 ]]; then
    printf '%s\n' "${options[@]}" | gum choose --no-limit --ordered --header "$header\n空格选中，回车确认" || true
    return
  fi

  echo "$header"
  local i=1
  for opt in "${options[@]}"; do
    echo "  $i) $opt"
    i=$((i + 1))
  done
  read -r -p "输入序号（逗号分隔，如 1,3,5）: " raw
  IFS=',' read -r -a picks <<<"$raw"
  for p in "${picks[@]}"; do
    p="${p//[[:space:]]/}"
    if [[ "$p" =~ ^[0-9]+$ ]] && ((p >= 1 && p <= ${#options[@]})); then
      echo "${options[$((p - 1))]}"
    fi
  done
}

badge_for_type() {
  case "$1" in
    official) printf '官方' ;;
    enhanced) printf '增强(非官方)' ;;
    *) printf '其他' ;;
  esac
}

risk_badge() {
  case "$1" in
    low) printf '低' ;;
    medium) printf '中' ;;
    high) printf '高' ;;
    *) printf '未知' ;;
  esac
}

ensure_project_root() {
  if [[ ! -f "$ROOT_DIR/pyproject.toml" ]]; then
    style_err "未找到项目根目录: $ROOT_DIR"
    exit 1
  fi
  cd "$ROOT_DIR"
}

activate_venv() {
  if [[ ! -f "$ROOT_DIR/.venv/bin/activate" ]]; then
    style_err "未找到虚拟环境: $ROOT_DIR/.venv/bin/activate"
    return 1
  fi
  # activate scripts can reference PS1 and unset vars
  export PS1="${PS1-}"
  set +u
  # shellcheck disable=SC1091
  source "$ROOT_DIR/.venv/bin/activate"
  set -u
}

require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    style_err "缺少命令: $cmd"
    return 1
  fi
}

backup_file() {
  local path="$1"
  [[ -e "$path" ]] || return 0
  cp "$path" "$path.bak.$(date +%Y%m%d_%H%M%S)"
}

safe_symlink() {
  local target="$1"
  local link_path="$2"

  mkdir -p "$(dirname -- "$link_path")"

  if [[ -L "$link_path" ]]; then
    rm -f "$link_path"
  elif [[ -e "$link_path" ]]; then
    mv "$link_path" "$link_path.bak.$(date +%Y%m%d_%H%M%S)"
  fi

  ln -s "$target" "$link_path"
}

add_step() {
  local id="$1"
  local title="$2"
  local type="$3"
  local risk="$4"
  local default_enabled="$5"
  local handler="$6"
  local command_preview="$7"
  local desc="$8"

  STEP_IDS+=("$id")
  STEP_TITLES+=("$title")
  STEP_TYPES+=("$type")
  STEP_RISKS+=("$risk")
  STEP_DEFAULTS+=("$default_enabled")
  STEP_HANDLERS+=("$handler")
  STEP_COMMANDS+=("$command_preview")
  STEP_DESCS+=("$desc")
}

register_steps() {
  # Official steps: align with docs/installation.md and docs/readme.md commands.
  add_step \
    "install_system_libs" \
    "安装系统图形依赖" \
    "official" \
    "high" \
    "1" \
    "step_install_system_libs" \
    "apt update && apt install -y libglu1-mesa libgl1 libegl1 libxrandr2 libxinerama1 libxcursor1 libxi6 libxext6 libx11-6" \
    "服务器环境依赖，来自 docs/installation.md"

  add_step \
    "set_glx_vendor" \
    "设置 NVIDIA GLX 变量" \
    "official" \
    "low" \
    "1" \
    "step_set_glx_vendor" \
    "export __GLX_VENDOR_LIBRARY_NAME=nvidia" \
    "来自 docs/installation.md"

  add_step \
    "uv_sync" \
    "同步 Python 依赖" \
    "official" \
    "medium" \
    "1" \
    "step_uv_sync" \
    "uv sync" \
    "来自 docs/installation.md"

  add_step \
    "clone_isaaclab" \
    "克隆 IsaacLab" \
    "official" \
    "low" \
    "1" \
    "step_clone_isaaclab" \
    "git clone https://github.com/lehome-official/IsaacLab.git third_party/IsaacLab" \
    "来自 docs/installation.md"

  add_step \
    "install_isaaclab" \
    "安装 IsaacLab" \
    "official" \
    "medium" \
    "1" \
    "step_install_isaaclab" \
    "source .venv/bin/activate && ./third_party/IsaacLab/isaaclab.sh -i none" \
    "来自 docs/installation.md"

  add_step \
    "install_lehome_pkg" \
    "安装 LeHome 包" \
    "official" \
    "medium" \
    "1" \
    "step_install_lehome_pkg" \
    "uv pip install -e ./source/lehome" \
    "来自 docs/installation.md"

  add_step \
    "download_assets" \
    "下载仿真资产" \
    "official" \
    "medium" \
    "1" \
    "step_download_assets" \
    "hf download lehome/asset_challenge --repo-type dataset --local-dir Assets" \
    "来自 docs/readme.md"

  add_step \
    "download_example_dataset" \
    "下载示例数据集" \
    "official" \
    "medium" \
    "1" \
    "step_download_example_dataset" \
    "hf download lehome/dataset_challenge_merged --repo-type dataset --local-dir Datasets/example" \
    "来自 docs/readme.md"

  # Enhanced steps: optional only.
  add_step \
    "install_uv_if_missing" \
    "安装 uv（缺失时）" \
    "enhanced" \
    "medium" \
    "0" \
    "step_install_uv_if_missing" \
    "curl -LsSf https://astral.sh/uv/install.sh | sh" \
    "非官方增强：自动安装 uv"

  add_step \
    "install_hf_cli" \
    "安装 HuggingFace CLI" \
    "enhanced" \
    "medium" \
    "0" \
    "step_install_hf_cli" \
    "uv pip install \"huggingface_hub[cli]\"" \
    "非官方增强：确保 hf 命令可用"

  add_step \
    "link_uv_cache" \
    "配置 uv 缓存软链" \
    "enhanced" \
    "high" \
    "0" \
    "step_link_uv_cache" \
    "ln -sf /root/data/.uv_cache ~/.cache/uv" \
    "非官方增强：迁移缓存到数据盘"

  add_step \
    "setup_isaacsim_symlink" \
    "配置 IsaacSim 软链" \
    "enhanced" \
    "medium" \
    "0" \
    "step_setup_isaacsim_symlink" \
    "python -c \"import isaacsim\" && ln -sf <isaacsim_path> third_party/IsaacLab/_isaac_sim" \
    "非官方增强：补齐 IsaacLab 与 IsaacSim 软链"

  add_step \
    "write_shell_shortcuts" \
    "写入 shell 快捷配置" \
    "enhanced" \
    "high" \
    "0" \
    "step_write_shell_shortcuts" \
    "write ~/.bashrc block" \
    "非官方增强：仅在 --write-bashrc 时执行"
}

find_step_idx_by_id() {
  local target="$1"
  local idx
  for idx in "${!STEP_IDS[@]}"; do
    if [[ "${STEP_IDS[$idx]}" == "$target" ]]; then
      echo "$idx"
      return 0
    fi
  done
  return 1
}

show_banner() {
  if [[ "$HAS_GUM" -eq 1 ]]; then
    gum format -- \
      "# LeHome 交互式环境安装器" \
      "官方流程基线: docs/readme.md + docs/installation.md" \
      "增强步骤默认关闭，可手动选择" \
      "日志: $LOG_FILE" \
      "执行模式: $MODE"
  else
    echo "LeHome 交互式环境安装器"
    echo "官方流程基线: docs/readme.md + docs/installation.md"
    echo "增强步骤默认关闭，可手动选择"
    echo "日志: $LOG_FILE"
    echo "执行模式: $MODE"
  fi
}

show_steps_table() {
  local idx
  for idx in "${!STEP_IDS[@]}"; do
    local num=$((idx + 1))
    local type risk default_mark
    type="$(badge_for_type "${STEP_TYPES[$idx]}")"
    risk="$(risk_badge "${STEP_RISKS[$idx]}")"
    default_mark=""
    if [[ "${STEP_DEFAULTS[$idx]}" == "1" ]]; then
      default_mark="默认"
    fi
    echo "$num. ${STEP_IDS[$idx]} [$type][风险:$risk] $default_mark"
    echo "   ${STEP_TITLES[$idx]}"
    echo "   命令: ${STEP_COMMANDS[$idx]}"
    echo "   说明: ${STEP_DESCS[$idx]}"
  done
}

show_step_list_only() {
  show_steps_table
}

is_high_risk() {
  [[ "$1" == "high" ]]
}

run_step_handler() {
  local handler="$1"
  if ! declare -f "$handler" >/dev/null 2>&1; then
    style_err "内部错误：未找到步骤函数 $handler"
    return 1
  fi
  "$handler"
}

record_success() {
  SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
}

record_skip() {
  SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
}

record_failure() {
  FAILED_COUNT=$((FAILED_COUNT + 1))
}

choose_failure_action() {
  if [[ "$HAS_GUM" -eq 1 ]]; then
    printf '重试\n跳过\n终止' | gum choose --header "步骤失败，选择后续操作" || echo "终止"
  else
    echo "步骤失败，选择后续操作:"
    echo "1) 重试"
    echo "2) 跳过"
    echo "3) 终止"
    local c
    read -r -p "请输入序号: " c
    case "$c" in
      1) echo "重试" ;;
      2) echo "跳过" ;;
      *) echo "终止" ;;
    esac
  fi
}

run_step_by_idx() {
  local idx="$1"
  local id title type risk handler cmd
  id="${STEP_IDS[$idx]}"
  title="${STEP_TITLES[$idx]}"
  type="${STEP_TYPES[$idx]}"
  risk="${STEP_RISKS[$idx]}"
  handler="${STEP_HANDLERS[$idx]}"
  cmd="${STEP_COMMANDS[$idx]}"

  echo
  style_dim "Step $((idx + 1)) | $id | $(badge_for_type "$type") | 风险: $(risk_badge "$risk")"
  style_dim "标题: $title"
  style_dim "命令: $cmd"
  log_line "准备执行 step=$id type=$type risk=$risk"

  if [[ "$DRY_RUN" -eq 1 ]]; then
    style_dim "DRY RUN: 未执行"
    record_skip
    log_line "DRY_RUN 跳过 step=$id"
    return 0
  fi

  if [[ "$MODE" == "confirm" ]]; then
    if ! ui_confirm "执行步骤 $id 吗？" 1; then
      style_warn "已跳过 $id"
      record_skip
      log_line "用户跳过 step=$id"
      return 0
    fi
  fi

  if is_high_risk "$risk"; then
    if ! ui_confirm "高风险步骤：$id。确认继续？" 0; then
      style_warn "已跳过高风险步骤 $id"
      record_skip
      log_line "用户取消高风险 step=$id"
      return 0
    fi
  fi

  while true; do
    set +e
    run_step_handler "$handler"
    local status=$?
    set -e

    if [[ $status -eq 0 ]]; then
      style_ok "完成: $id"
      record_success
      log_line "完成 step=$id"
      return 0
    fi

    style_err "失败: $id (exit=$status)"
    log_line "失败 step=$id exit=$status"

    if [[ "$MODE" == "auto" || "$ASSUME_YES" -eq 1 ]]; then
      record_failure
      return "$status"
    fi

    local action
    action="$(choose_failure_action)"
    case "$action" in
      重试)
        ;;
      跳过)
        record_skip
        log_line "失败后跳过 step=$id"
        return 0
        ;;
      终止|*)
        record_failure
        return "$status"
        ;;
    esac
  done
}

run_default_flow() {
  local idx
  for idx in "${!STEP_IDS[@]}"; do
    if [[ "${STEP_DEFAULTS[$idx]}" != "1" ]]; then
      continue
    fi
    if ! run_step_by_idx "$idx"; then
      return 1
    fi
  done
}

run_steps_by_ids() {
  local sid idx
  for sid in "$@"; do
    if ! idx="$(find_step_idx_by_id "$sid")"; then
      style_err "未知步骤 ID: $sid"
      return 1
    fi
    if ! run_step_by_idx "$idx"; then
      return 1
    fi
  done
}

run_multi_select() {
  local options=()
  local idx
  for idx in "${!STEP_IDS[@]}"; do
    local item
    item="${STEP_IDS[$idx]} | $(badge_for_type "${STEP_TYPES[$idx]}") | 风险:$(risk_badge "${STEP_RISKS[$idx]}") | ${STEP_TITLES[$idx]}"
    options+=("$item")
  done

  local picked_lines
  picked_lines="$(ui_choose_many_lines "选择要执行的步骤" "${options[@]}")"
  if [[ -z "$picked_lines" ]]; then
    style_warn "未选择任何步骤"
    return 0
  fi

  local selected_ids=()
  local line
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    selected_ids+=("${line%% | *}")
  done <<<"$picked_lines"

  if [[ ${#selected_ids[@]} -eq 0 ]]; then
    style_warn "未解析到有效步骤"
    return 0
  fi

  run_steps_by_ids "${selected_ids[@]}"
}

set_mode_interactive() {
  local choice
  choice="$(ui_choose_one "选择执行模式" "逐步确认（每步询问）" "自动执行（不再询问）")"
  case "$choice" in
    "自动执行（不再询问）")
      MODE="auto"
      ASSUME_YES=1
      ;;
    *)
      MODE="confirm"
      ASSUME_YES=0
      ;;
  esac
  style_dim "当前执行模式: $MODE"
  log_line "执行模式切换为 $MODE"
}

main_menu() {
  while true; do
    local choice
    choice="$(ui_choose_one "选择操作" "执行全流程" "选择步骤执行" "仅浏览命令" "切换执行模式" "退出")"
    case "$choice" in
      "执行全流程")
        run_default_flow || return 1
        ;;
      "选择步骤执行")
        run_multi_select || return 1
        ;;
      "仅浏览命令")
        show_steps_table
        ;;
      "切换执行模式")
        set_mode_interactive
        ;;
      "退出"|*)
        style_dim "退出。"
        return 0
        ;;
    esac
  done
}

print_summary() {
  echo
  style_dim "执行摘要: success=$SUCCESS_COUNT skip=$SKIPPED_COUNT failed=$FAILED_COUNT"
  style_dim "日志文件: $LOG_FILE"
  if [[ "$WRITE_BASHRC" -eq 0 ]]; then
    style_dim "提示: 默认未改写 ~/.bashrc（如需写入请加 --write-bashrc）"
  fi
}

# ------------------------
# Step handlers
# ------------------------

step_install_system_libs() {
  local priv=()
  if [[ "$(id -u)" -ne 0 ]]; then
    priv=(sudo)
  fi

  "${priv[@]}" apt update
  "${priv[@]}" apt install -y \
    libglu1-mesa \
    libgl1 \
    libegl1 \
    libxrandr2 \
    libxinerama1 \
    libxcursor1 \
    libxi6 \
    libxext6 \
    libx11-6
}

step_set_glx_vendor() {
  export __GLX_VENDOR_LIBRARY_NAME=nvidia
  style_ok "已设置 __GLX_VENDOR_LIBRARY_NAME=nvidia"
}

step_uv_sync() {
  ensure_project_root
  require_cmd uv
  uv sync
}

step_clone_isaaclab() {
  ensure_project_root
  mkdir -p "$ROOT_DIR/third_party"
  if [[ -d "$ROOT_DIR/third_party/IsaacLab/.git" ]]; then
    style_dim "IsaacLab 已存在，跳过 clone"
    return 0
  fi
  git clone https://github.com/lehome-official/IsaacLab.git "$ROOT_DIR/third_party/IsaacLab"
}

step_install_isaaclab() {
  ensure_project_root
  activate_venv
  if [[ ! -x "$ROOT_DIR/third_party/IsaacLab/isaaclab.sh" ]]; then
    style_err "未找到 $ROOT_DIR/third_party/IsaacLab/isaaclab.sh"
    return 1
  fi
  "$ROOT_DIR/third_party/IsaacLab/isaaclab.sh" -i none
}

step_install_lehome_pkg() {
  ensure_project_root
  activate_venv
  require_cmd uv
  uv pip install -e "$ROOT_DIR/source/lehome"
}

step_download_assets() {
  ensure_project_root
  activate_venv
  require_cmd hf
  hf download lehome/asset_challenge --repo-type dataset --local-dir "$ROOT_DIR/Assets"
}

step_download_example_dataset() {
  ensure_project_root
  activate_venv
  require_cmd hf
  hf download lehome/dataset_challenge_merged --repo-type dataset --local-dir "$ROOT_DIR/Datasets/example"
}

step_install_uv_if_missing() {
  if command -v uv >/dev/null 2>&1; then
    style_dim "uv 已存在，跳过安装"
    return 0
  fi
  curl -LsSf https://astral.sh/uv/install.sh | sh
  export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"
  require_cmd uv
}

step_install_hf_cli() {
  ensure_project_root
  activate_venv
  require_cmd uv
  uv pip install "huggingface_hub[cli]"
}

step_link_uv_cache() {
  local target="/root/data/.uv_cache"
  local link_path="$HOME/.cache/uv"

  mkdir -p "$target" "$HOME/.cache"

  if [[ -e "$link_path" || -L "$link_path" ]]; then
    if ! ui_confirm "将重置 $link_path 并重建软链，确认继续？" 0; then
      return 1
    fi
    rm -rf "$link_path"
  fi

  ln -s "$target" "$link_path"
}

step_setup_isaacsim_symlink() {
  ensure_project_root
  activate_venv

  python -c "import isaacsim" >/dev/null
  local pkg
  pkg="$(python -c "import isaacsim, os; print(os.path.dirname(isaacsim.__file__))")"
  [[ -n "$pkg" ]] || return 1

  safe_symlink "$pkg" "$ROOT_DIR/third_party/IsaacLab/_isaac_sim"
}

step_write_shell_shortcuts() {
  if [[ "$WRITE_BASHRC" -ne 1 ]]; then
    style_warn "未传 --write-bashrc，跳过写入 ~/.bashrc"
    return 0
  fi

  local bashrc="$HOME/.bashrc"
  local begin="# --- LeHome env v3 ---"
  local end="# --- End LeHome env v3 ---"

  touch "$bashrc"
  backup_file "$bashrc"

  awk -v begin="$begin" -v end="$end" '
    $0 == begin { skip=1; next }
    $0 == end { skip=0; next }
    !skip { print }
  ' "$bashrc" >"$bashrc.tmp"

  cat >>"$bashrc.tmp" <<EOB
$begin
export PATH="\$HOME/.local/bin:\$HOME/.cargo/bin:\$PATH"
go() {
  cd "$ROOT_DIR" && source .venv/bin/activate
}
$end
EOB

  mv "$bashrc.tmp" "$bashrc"
  style_ok "已写入 ~/.bashrc（已备份）"
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --mode)
        [[ $# -ge 2 ]] || { style_err "--mode 需要参数"; exit 1; }
        MODE="$2"
        case "$MODE" in
          confirm|auto) ;;
          *) style_err "--mode 仅支持 confirm|auto"; exit 1 ;;
        esac
        shift 2
        ;;
      --yes|-y)
        ASSUME_YES=1
        MODE="auto"
        shift
        ;;
      --dry-run)
        DRY_RUN=1
        shift
        ;;
      --list)
        LIST_ONLY=1
        shift
        ;;
      --step)
        [[ $# -ge 2 ]] || { style_err "--step 需要 step_id"; exit 1; }
        REQUESTED_STEP_IDS+=("$2")
        shift 2
        ;;
      --write-bashrc)
        WRITE_BASHRC=1
        shift
        ;;
      --log-file)
        [[ $# -ge 2 ]] || { style_err "--log-file 需要路径"; exit 1; }
        LOG_FILE="$2"
        mkdir -p "$(dirname "$LOG_FILE")"
        shift 2
        ;;
      -h|--help)
        print_usage
        exit 0
        ;;
      *)
        style_err "不支持的参数: $1"
        print_usage
        exit 1
        ;;
    esac
  done
}

main() {
  if command -v gum >/dev/null 2>&1; then
    HAS_GUM=1
  fi

  parse_args "$@"
  register_steps

  log_line "启动 env.sh mode=$MODE dry_run=$DRY_RUN write_bashrc=$WRITE_BASHRC has_gum=$HAS_GUM"

  if [[ "$LIST_ONLY" -eq 1 ]]; then
    show_step_list_only
    exit 0
  fi

  if [[ ${#REQUESTED_STEP_IDS[@]} -gt 0 ]]; then
    show_banner
    local requested_status=0
    run_steps_by_ids "${REQUESTED_STEP_IDS[@]}" || requested_status=$?
    print_summary
    exit "$requested_status"
  fi

  show_banner
  main_menu
  print_summary
}

main "$@"
