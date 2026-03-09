#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

usage() {
    cat <<'USAGE'
Usage: bash start/v2.0/allinone.sh <command> [args...]

统一入口：
  setup [--install-system-libs] [--with-full-dataset]
  install [args...]
  finalize
  data [args...]
  train [args...]
  eval [args...]
  xvla [args...]
  wandb [args...]
  vpn [args...]
  save <version>

示例：
  bash start/v2.0/allinone.sh setup --install-system-libs --with-full-dataset
  bash start/v2.0/allinone.sh install --install-system-libs
  bash start/v2.0/allinone.sh train act 1000
  bash start/v2.0/allinone.sh xvla
USAGE
}

COMMAND="${1:-help}"
if [[ $# -gt 0 ]]; then
    shift
fi

case "$COMMAND" in
    setup)
        exec_v2_script "setup.sh" "$@"
        ;;
    install)
        exec_v2_script "install.sh" "$@"
        ;;
    finalize)
        exec_v2_script "finalize.sh" "$@"
        ;;
    data)
        exec_v2_script "data.sh" "$@"
        ;;
    train)
        exec_v2_script "train.sh" "$@"
        ;;
    eval)
        exec_v2_script "eval.sh" "$@"
        ;;
    xvla)
        exec_v2_script "xvla.sh" "$@"
        ;;
    wandb)
        exec_v2_script "wandb.sh" "$@"
        ;;
    vpn)
        exec_v2_script "vpn.sh" "$@"
        ;;
    save)
        exec_v2_script "save.sh" "$@"
        ;;
    -h|--help|help|"")
        usage
        ;;
    *)
        die "❌ 不支持的命令: $COMMAND（使用 --help 查看可用命令）"
        ;;
esac
