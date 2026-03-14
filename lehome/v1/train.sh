#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOC_PATH="$ROOT_DIR/docs/step-core-commands.md"
LOG_DIR="$ROOT_DIR/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/interactive-step-runner-$(date +%Y%m%d-%H%M%S).log"
ASSUME_YES=0
EXEC_MODE_LABEL="逐步确认（每步询问）"

install_gum_prompt() {
  printf '[提示] gum 未安装。\n'
  read -r -p "需要现在自动安装 gum 吗？[y/N]: " INSTALL_GUM
  case "${INSTALL_GUM,,}" in
    y|yes)
      curl -fsSL https://gum.run/install.sh | sh
      ;;
    *)
      echo "未安装 gum，脚本退出。"
      exit 1
      ;;
  esac
}

if ! command -v gum >/dev/null 2>&1; then
  install_gum_prompt
fi

typeset -a STEP_CMDS STEP_DESC STEP_TYPE STEP_MODE STEP_DISPLAY

add_step() {
  STEP_TYPE+=("$1")
  STEP_CMDS+=("$2")
  STEP_DESC+=("$3")
  STEP_MODE+=("${4:-cmd}")
  STEP_DISPLAY+=("$5")
}

add_step official "sudo apt update && sudo apt install -y libglu1-mesa libgl1 libegl1 libxrandr2 libxinerama1 libxcursor1 libxi6 libxext6 libx11-6" "官方基础：安装系统图形依赖" "cmd" "sudo apt update && sudo apt install -y libglu1-mesa ..."
add_step official "export __GLX_VENDOR_LIBRARY_NAME=nvidia" "官方基础：锁定 NVIDIA GLX 供应商" "cmd" "export __GLX_VENDOR_LIBRARY_NAME=nvidia"
add_step enhanced "mkdir -p /root/data/.uv_cache" "增强：准备 data 盘缓存目录（uv 之前执行）" "cmd" "mkdir -p /root/data/.uv_cache"
add_step enhanced "mkdir -p ~/.cache" "增强：保证本地缓存根目录存在" "cmd" "mkdir -p ~/.cache"
add_step enhanced "rm -rf ~/.cache/uv" "增强：清理旧 uv 缓存目录" "cmd" "rm -rf ~/.cache/uv"
add_step enhanced "ln -sf /root/data/.uv_cache ~/.cache/uv" "增强：建立 uv 缓存软链" "cmd" "ln -sf /root/data/.uv_cache ~/.cache/uv"
add_step official "if ! command -v uv >/dev/null 2>&1; then curl -LsSf https://astral.sh/uv/install.sh | sh; else echo 'uv 已安装，跳过'; fi" "官方 UV：安装 uv 工具" "cmd" "curl -LsSf https://astral.sh/uv/install.sh | sh"
add_step official "if [ ! -d \"$ROOT_DIR\" ]; then git clone https://github.com/lehome-official/lehome-challenge.git; fi" "官方 Step1：克隆主仓库（已存在则跳过）" "cmd" "git clone https://github.com/lehome-official/lehome-challenge.git"
add_step official "cd \"$ROOT_DIR\"" "官方：进入仓库目录" "cmd" "cd lehome-challenge"
add_step official "cd \"$ROOT_DIR\" && uv sync" "官方 Step2：创建虚拟环境并同步依赖" "cmd" "uv sync"
add_step official "cd \"$ROOT_DIR\" && mkdir -p third_party" "官方：准备第三方目录" "cmd" "mkdir -p third_party"
add_step official "cd \"$ROOT_DIR\" && if [ ! -d third_party/IsaacLab ]; then git clone https://github.com/lehome-official/IsaacLab.git third_party/IsaacLab; fi" "官方 Step3：获取 IsaacLab" "cmd" "git clone https://github.com/lehome-official/IsaacLab.git third_party/IsaacLab"
add_step official "cd \"$ROOT_DIR\" && source .venv/bin/activate" "官方 Step4：激活虚拟环境" "cmd" "source .venv/bin/activate"
add_step official "cd \"$ROOT_DIR\" && source .venv/bin/activate && ./third_party/IsaacLab/isaaclab.sh -i none" "官方 Step4：构建 IsaacLab" "cmd" "./third_party/IsaacLab/isaaclab.sh -i none"
add_step official "cd \"$ROOT_DIR\" && source .venv/bin/activate && uv pip install -e ./source/lehome" "官方 Step5：安装 LeHome 包" "cmd" "uv pip install -e ./source/lehome"
add_step enhanced "cd \"$ROOT_DIR\" && source .venv/bin/activate && uv pip install \"huggingface_hub[cli]\"" "增强：安装 HuggingFace CLI" "cmd" "uv pip install \"huggingface_hub[cli]\""
add_step official "cd \"$ROOT_DIR\" && source .venv/bin/activate && if [ ! -d Assets ]; then hf download lehome/asset_challenge --repo-type dataset --local-dir Assets; else echo 'Assets 已存在，跳过下载'; fi" "官方 Quick Start：下载仿真资产" "cmd" "hf download lehome/asset_challenge --repo-type dataset --local-dir Assets"
add_step official "cd \"$ROOT_DIR\" && source .venv/bin/activate && if [ ! -d Datasets/example ]; then hf download lehome/dataset_challenge_merged --repo-type dataset --local-dir Datasets/example; else echo 'Datasets/example 已存在，跳过下载'; fi" "官方 Quick Start：下载示例数据集" "cmd" "hf download lehome/dataset_challenge_merged --repo-type dataset --local-dir Datasets/example"
add_step enhanced "sed -i '/# --- LeHome 环境配置 ---/,/# --- End LeHome ---/d' ~/.bashrc" "增强：清理旧自动激活配置块" "cmd" "sed -i '/# --- LeHome 环境配置 ---/,/# --- End LeHome ---/d' ~/.bashrc"
add_step enhanced "append_bashrc_block" "增强：追加 PATH、自动激活、alias 配置块" "func" "cat <<'EOF' >> ~/.bashrc"
add_step enhanced "export PATH=\"$HOME/.local/bin:$HOME/.cargo/bin:$PATH\"" "增强：刷新当前终端 PATH" "cmd" "export PATH=\"$HOME/.local/bin:$HOME/.cargo/bin:$PATH\""
add_step official "if [ -d /root/data/lehome-challenge ]; then cd /root/data/lehome-challenge; else cd \"$ROOT_DIR\"; fi" "官方习惯：进入 /root/data/lehome-challenge（无则退回当前仓库）" "cmd" "cd /root/data/lehome-challenge"
add_step official "source .venv/bin/activate" "官方：再次激活虚拟环境" "cmd" "source .venv/bin/activate"
add_step official "python -c \"import isaacsim\"" "官方 IsaacSim：触发 NVIDIA 授权" "cmd" "python -c \"import isaacsim\""
add_step official "ISAACSIM_PKG_PATH=$(python -c \"import isaacsim, os; print(os.path.dirname(isaacsim.__file__))\")" "官方 IsaacSim：记录物理安装路径" "cmd" "ISAACSIM_PKG_PATH=$(python -c \"import isaacsim, os; print(os.path.dirname(isaacsim.__file__))\")"
add_step official "mkdir -p third_party/IsaacLab" "官方：确认软链目标目录存在" "cmd" "mkdir -p third_party/IsaacLab"
add_step official "rm -rf third_party/IsaacLab/_isaac_sim" "官方/维护：清理旧 IsaacSim 软链" "cmd" "rm -rf third_party/IsaacLab/_isaac_sim"
add_step official "ln -sf \"$ISAACSIM_PKG_PATH\" third_party/IsaacLab/_isaac_sim" "官方要求：建立 IsaacLab -> IsaacSim 软链" "cmd" "ln -sf \"$ISAACSIM_PKG_PATH\" third_party/IsaacLab/_isaac_sim"

append_bashrc_block() {
  cat <<'EOB' >> ~/.bashrc
# --- LeHome 环境配置 ---
export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"

cd_activate_venv() {
    builtin cd "$@" || return
    if [ -f ".venv/bin/activate" ]; then
        if [ "${VIRTUAL_ENV:-}" != "$(pwd)/.venv" ]; then
            source .venv/bin/activate
        fi
    fi
}
alias cd='cd_activate_venv'
alias go='cd /root/data/lehome-challenge && source .venv/bin/activate'
alias save='bash /root/data/lehome-challenge/start/step_git.sh'

if [ -f ".venv/bin/activate" ]; then source .venv/bin/activate; fi
# --- End LeHome ---
EOB
}

badge_for_type() {
  case "$1" in
    official) printf "官方" ;;
    enhanced) printf "增强" ;;
    *) printf "其他" ;;
  esac
}

log_line() {
  printf '[%s] %s\n' "$(date '+%F %T')" "$*" >> "$LOG_FILE"
}

select_execution_mode() {
  local choice
  choice=$(gum choose --header "选择执行模式" "逐步确认（每步询问）" "自动执行（不再询问）" || true)
  case "$choice" in
    "自动执行（不再询问）")
      ASSUME_YES=1
      EXEC_MODE_LABEL="自动执行（不再询问）"
      ;;
    *)
      ASSUME_YES=0
      EXEC_MODE_LABEL="逐步确认（每步询问）"
      ;;
  esac
  gum style --foreground 245 "当前执行模式：${EXEC_MODE_LABEL}"
  log_line "执行模式设为: ${EXEC_MODE_LABEL}"
}

show_banner() {
  gum format -- "# LeHome 交互式 Step Runner" "当前脚本读取: ${DOC_PATH}" "日志: ${LOG_FILE}" "提示：标记为 '增强' 的命令为脚本附加优化，'官方' 表示 README/官方文档指令。" "执行模式：${EXEC_MODE_LABEL}"
}

show_steps_table() {
  local idx
  for idx in "${!STEP_CMDS[@]}"; do
    local num=$((idx + 1))
    gum format -- "${num}. [$(badge_for_type "${STEP_TYPE[$idx]}")] ${STEP_DISPLAY[$idx]}" "    ${STEP_DESC[$idx]}"
  done
}

execute_cmd() {
  local mode="$1"
  local cmd="$2"
  if [ "$mode" = "func" ]; then
    $cmd
  else
    eval "$cmd"
  fi
}

run_step() {
  local idx="$1"
  local num=$((idx + 1))
  local badge="$(badge_for_type "${STEP_TYPE[$idx]}")"
  gum format -- "## Step ${num}" "类型：$badge" "命令：${STEP_DISPLAY[$idx]}" "说明：${STEP_DESC[$idx]}"
  log_line "Step ${num} (${badge}): ${STEP_DISPLAY[$idx]}"

  if [[ "${DRY_RUN:-0}" == 1 ]]; then
    gum style --foreground 244 "DRY RUN 模式：仅展示命令，未执行。"
    return
  fi

  if [[ "${ASSUME_YES:-0}" -ne 1 ]]; then
    local proceed
    if ! gum confirm --affirmative "执行" --negative "跳过" --default=true "执行 Step ${num} 吗？"; then
      gum style --foreground 214 "用户选择跳过 Step ${num}"
      log_line "Step ${num} 用户跳过"
      return
    fi
  fi

  set +e
  execute_cmd "${STEP_MODE[$idx]}" "${STEP_CMDS[$idx]}"
  local status=$?
  set -e

  if [ $status -ne 0 ]; then
    gum style --foreground 196 "命令失败 (exit $status)"
    log_line "Step ${num} 失败: exit $status"
    local action
    action=$(printf '重试\n跳过\n终止' | gum choose --header "选择下一步" || printf '终止')
    case "$action" in
      重试)
        run_step "$idx"
        return
        ;;
      跳过)
        gum style --foreground 214 "已跳过 Step ${num}"
        log_line "Step ${num} 跳过"
        return
        ;;
      终止|*)
        gum style --foreground 196 "终止执行"
        exit 1
        ;;
    esac
  else
    gum style --foreground 46 "Step ${num} 完成"
    log_line "Step ${num} 完成"
  fi
}

run_all() {
  local idx
  for idx in "${!STEP_CMDS[@]}"; do
    run_step "$idx"
  done
}

run_single() {
  local options=()
  local idx
  for idx in "${!STEP_CMDS[@]}"; do
    local num=$((idx + 1))
    options+=("${idx}:::${num}. [$(badge_for_type "${STEP_TYPE[$idx]}")] ${STEP_DISPLAY[$idx]}")
  done
  local selected
  selected=$(printf '%s\n' "${options[@]}" | gum choose --header "选择要运行的步骤" | awk -F':::' '{print $1}')
  [ -z "$selected" ] && return
  run_step "$selected"
}

main_menu() {
  while true; do
    local choice
    choice=$(printf '执行全流程\n选择单步\n仅浏览命令\n切换执行模式\n退出' | gum choose --header "选择操作" || printf '退出')
    case "$choice" in
      执行全流程)
        run_all
        ;;
      选择单步)
        run_single
        ;;
      仅浏览命令)
        show_steps_table
        ;;
      切换执行模式)
        select_execution_mode
        show_banner
        ;;
      退出|*)
        gum style --foreground 245 "退出 Step Runner"
        exit 0
        ;;
    esac
  done
}

select_execution_mode
show_banner
main_menu
