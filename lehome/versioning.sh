#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

DEFAULT_GITHUB_USER="sudo-yf"
DEFAULT_GITHUB_EMAIL="$DEFAULT_GITHUB_USER@users.noreply.github.com"
VERSIONS_FILE="$PROJECT_ROOT/VERSIONS.md"

normalize_version_tag() {
    local raw="${1:-}"
    [[ -n "$raw" ]] || die "❌ 版本号不能为空。"
    if [[ "$raw" == v* ]]; then
        printf '%s\n' "$raw"
    else
        printf 'v%s\n' "$raw"
    fi
}

configure_git_identity() {
    section "检查 Git 身份"
    if [[ -z "$(git config user.name || true)" ]]; then
        git config --global user.name "$DEFAULT_GITHUB_USER"
        git config --global user.email "$DEFAULT_GITHUB_EMAIL"
        ok "✅ 已设置 Git 身份: $DEFAULT_GITHUB_USER"
    else
        ok "✅ 当前 Git 身份: $(git config user.name)"
    fi
}

ensure_personal_origin() {
    section "检查仓库远端"
    local main_origin
    main_origin="$(git remote get-url origin 2>/dev/null || echo '')"
    if [[ "$main_origin" == *"lehome-official"* ]]; then
        warn "⚠️ 发现 origin 仍指向官方仓库，自动切换到个人仓库。"
        git remote set-url origin "https://github.com/$DEFAULT_GITHUB_USER/lehome-challenge.git"
        git remote add upstream "https://github.com/lehome-official/lehome-challenge.git" 2>/dev/null || true
    fi
    ok "✅ origin: $(git remote get-url origin 2>/dev/null || echo '<missing>')"
}

collect_tag_rows() {
    git for-each-ref refs/tags --sort=-creatordate --format='%(refname:short)|%(creatordate:short)|%(objectname:short)|%(subject)'
}

render_versions_file() {
    local pending_tag="${1:-}"
    local pending_date="${2:-}"
    local pending_commit="${3:-}"
    local pending_note="${4:-}"

    {
        echo "# Versions"
        echo
        printf '%s\n' '本文件记录通过 `save` 流程创建的版本标签，便于快速检索。'
        echo
        echo "| Version | Date | Commit | Notes |"
        echo "| --- | --- | --- | --- |"
        if [[ -n "$pending_tag" ]]; then
            printf '| `%s` | `%s` | `%s` | %s |\n' "$pending_tag" "$pending_date" "$pending_commit" "${pending_note//|/ /}"
        fi
        collect_tag_rows | while IFS='|' read -r tag date commit subject; do
            [[ -n "$tag" ]] || continue
            if [[ -n "$pending_tag" && "$tag" == "$pending_tag" ]]; then
                continue
            fi
            printf '| `%s` | `%s` | `%s` | %s |\n' "$tag" "$date" "$commit" "${subject//|/ /}"
        done
    } > "$VERSIONS_FILE"
}

show_versions() {
    ensure_repo_root
    render_versions_file
    section "版本索引"
    cat "$VERSIONS_FILE"
}

save_version() {
    ensure_repo_root
    ensure_path

    local version_arg=""
    local note=""
    local force_tag=false
    local local_only=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --note)
                shift
                [[ $# -gt 0 ]] || die "❌ --note 需要一个备注字符串。"
                note="$1"
                ;;
            --force-tag)
                force_tag=true
                ;;
            --local-only)
                local_only=true
                ;;
            -h|--help)
                cat <<'USAGE'
Usage: bash lehome/allinone.sh save <version> [note...]
       bash lehome/allinone.sh save <version> --note "your note"

Options:
  --note <text>    版本备注
  --force-tag      允许覆盖已有 tag
  --local-only     只在本地提交和打 tag，不推送远端
USAGE
                return 0
                ;;
            *)
                if [[ -z "$version_arg" ]]; then
                    version_arg="$1"
                else
                    if [[ -n "$note" ]]; then
                        note+=" "
                    fi
                    note+="$1"
                fi
                ;;
        esac
        shift
    done

    [[ -n "$version_arg" ]] || die "❌ 忘记写版本号啦！例如: just save 3 xvla-wandb"

    local version tag commit_msg branch commit_short today tag_subject
    tag="$(normalize_version_tag "$version_arg")"
    today="$(date +%Y-%m-%d)"
    tag_subject="${note:-Auto save $tag}"
    commit_msg="save: $tag"
    if [[ -n "$note" ]]; then
        commit_msg+=" - $note"
    fi

    section "准备保存版本"
    kv "Tag" "$tag"
    kv "Note" "${note:-<none>}"
    kv "Local only" "$local_only"
    kv "Force tag" "$force_tag"

    if git rev-parse "$tag" >/dev/null 2>&1; then
        if [[ "$force_tag" != true ]]; then
            die "❌ 标签 $tag 已存在。默认不覆盖；如确需覆盖，请显式传 --force-tag。"
        fi
        warn "⚠️ 标签 $tag 已存在，将按要求覆盖。"
    fi

    activate_venv || true
    configure_git_identity
    ensure_personal_origin

    section "提交当前工作区"
    git add -A
    if git diff --cached --quiet; then
        warn "⚠️ 当前没有未提交改动，将创建一个空的版本提交。"
        git commit --allow-empty -m "$commit_msg"
    else
        git commit -m "$commit_msg"
    fi

    commit_short="$(git rev-parse --short HEAD)"

    section "写入版本标签"
    if [[ "$force_tag" == true ]]; then
        git tag -d "$tag" >/dev/null 2>&1 || true
    fi
    git tag -a "$tag" -m "$tag_subject"
    ok "✅ 已创建标签: $tag"

    section "刷新版本索引"
    render_versions_file "$tag" "$today" "$commit_short" "$tag_subject"
    git add "$VERSIONS_FILE"
    if git diff --cached --quiet; then
        warn "⚠️ VERSIONS.md 无变化，跳过索引提交。"
    else
        git commit -m "docs: refresh version index for $tag" >/dev/null
        ok "✅ 已更新版本索引提交"
    fi

    if [[ "$local_only" != true ]]; then
        section "推送远端"
        branch="$(git rev-parse --abbrev-ref HEAD)"
        cmd_preview "git push origin $branch"
        git push origin "$branch"
        if [[ "$force_tag" == true ]]; then
            git push origin ":refs/tags/$tag" >/dev/null 2>&1 || true
        fi
        cmd_preview "git push origin $tag"
        git push origin "$tag"
        ok "✅ 已推送分支与标签"
    else
        warn "⚠️ 已跳过远端推送（--local-only）"
    fi

    section "版本保存完成"
    kv "Tag" "$tag"
    kv "Tagged commit" "$commit_short"
    kv "Index" "$VERSIONS_FILE"
}
