#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
source "$SCRIPT_DIR/versioning.sh"

usage() {
    cat <<'USAGE'
Usage: bash lehome/allinone.sh <command> [args...]

统一入口：
  setup [--install-system-libs] [--with-full-dataset]
  prepare [--install-system-libs]
  data [args...]
  train [args...]
  eval [args...]
  xvla [args...]
  wandb [args...]
  sweep [args...]
  vpn [args...]
  save <version> [note...]
  versions

示例：
  bash lehome/allinone.sh setup --install-system-libs --with-full-dataset
  bash lehome/allinone.sh prepare --install-system-libs
  bash lehome/allinone.sh train act 1000
  bash lehome/allinone.sh xvla
  bash lehome/allinone.sh versions
USAGE
}

run_setup() {
    local prepare_args=()
    local data_args=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --install-system-libs)
                prepare_args+=("$1")
                ;;
            --with-full-dataset)
                data_args+=("$1")
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                die "❌ setup 不支持的参数: $1"
                ;;
        esac
        shift
    done

    section "执行 LeHome 主流程"
    kv "Prepare args" "${prepare_args[*]:-(none)}"
    kv "Data args" "${data_args[*]:-(none)}"
    invoke_local_script "prepare.sh" "${prepare_args[@]}"
    invoke_local_script "data.sh" "${data_args[@]}"
    ok "✅ LeHome 主流程执行完成"
}

COMMAND="${1:-help}"
if [[ $# -gt 0 ]]; then
    shift
fi

case "$COMMAND" in
    setup)
        run_setup "$@"
        ;;
    prepare)
        exec_local_script "prepare.sh" "$@"
        ;;
    data)
        exec_local_script "data.sh" "$@"
        ;;
    train)
        exec_local_script "train.sh" "$@"
        ;;
    eval)
        exec_local_script "eval.sh" "$@"
        ;;
    xvla)
        exec_local_script "xvla.sh" "$@"
        ;;
    wandb)
        exec_local_script "wandb.sh" "$@"
        ;;
    sweep)
        exec_local_script "sweep.sh" "$@"
        ;;
    vpn)
        exec bash "$SCRIPT_DIR/v1/step_vpn.sh" "$@"
        ;;
    save)
        save_version "$@"
        ;;
    versions)
        show_versions
        ;;
    -h|--help|help|"")
        usage
        ;;
    *)
        die "❌ 不支持的命令: $COMMAND（使用 --help 查看可用命令）"
        ;;
esac
