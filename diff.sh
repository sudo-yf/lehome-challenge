#!/bin/bash
REPO="/root/data/lehome-challenge"
LOG="$REPO/diff.log"
UPSTREAM="upstream/main"

cd "$REPO" || exit 1

if ! git remote | grep -q "^upstream$"; then
    git remote add upstream https://github.com/lehome-official/lehome-challenge.git
fi

git fetch upstream --quiet

{
    echo "生成时间: $(date '+%Y-%m-%d %H:%M:%S')"
    echo ""
    echo "【M 修改】"
    git diff "$UPSTREAM" HEAD --name-status | grep "^M" || echo "  (无)"
    echo ""
    echo "【A 新增】"
    git diff "$UPSTREAM" HEAD --name-status | grep "^A" || echo "  (无)"
    echo ""
    echo "【D 删除】"
    git diff "$UPSTREAM" HEAD --name-status | grep "^D" || echo "  (无)"
    echo ""
    echo "【修改详情】"
    echo "----------------------------------------"
    git diff "$UPSTREAM" HEAD --diff-filter=M -- scripts/ source/ | while IFS= read -r line; do
        if [[ "$line" =~ ^"diff --git" ]]; then
            echo ""
            echo ">>> ${line#diff --git a/}"
        elif [[ "$line" =~ ^@@ ]]; then
            echo "$line"
        elif [[ "$line" =~ ^\+\+\+ ]] || [[ "$line" =~ ^"---" ]] || [[ "$line" =~ ^"index" ]]; then
            :
        elif [[ "$line" =~ ^\+ ]]; then
            echo "新增: ${line:1}"
        elif [[ "$line" =~ ^\- ]]; then
            echo "删除: ${line:1}"
        fi
    done
} > "$LOG"

echo "[done] $LOG"
