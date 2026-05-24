#!/bin/bash
# goal-dual/scripts/commit-iter.sh — イテレーションごとのコミット / no-git 時はスナップショット保存
# Usage: bash commit-iter.sh <iteration> <"pass"|"wip"> [commit-message-suffix]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

ITERATION="${1:-0}"
KIND="${2:-wip}"       # "pass" or "wip"
SUFFIX="${3:-}"

NO_GIT=$(jq -r '.no_git // false' .goal-dual/state.json 2>/dev/null)
GOAL_TEXT=$(state_get "goal_text")
GOAL_SUMMARY=$(python3 -c "import sys; t=sys.argv[1][:60].rstrip(); print(t)" "$GOAL_TEXT")

# --- no-git モード: スナップショット保存 ---
if [ "$NO_GIT" = "true" ]; then
  SNAP_DIR=".goal-dual/history/iter-${ITERATION}"
  mkdir -p "$SNAP_DIR"

  # .goal-dual/ 管理ファイルをコピー（config.json は state.json に統合済みのため除外）
  for f in progress.txt goal.md state.json; do
    [ -f ".goal-dual/$f" ] && cp ".goal-dual/$f" "$SNAP_DIR/"
  done
  # synthesized-*.json
  find .goal-dual/state/evaluations -name "synthesized-*.json" 2>/dev/null \
    | while read -r sf; do cp "$sf" "$SNAP_DIR/"; done
  # final-review.md（pass 時のみ）
  if [ "$KIND" = "pass" ] && [ -f .goal-dual/state/final-review.md ]; then
    cp .goal-dual/state/final-review.md "$SNAP_DIR/"
  fi

  # 変更された実装ファイルを snapshot にコピー（find で最終更新がスナップショット時点より新しいもの）
  STARTED_AT=$(jq -r '.started_at // ""' .goal-dual/state.json 2>/dev/null || echo "")
  if [ -n "$STARTED_AT" ]; then
    find . -newer .goal-dual/state.json \
      -not -path './.goal-dual/*' \
      -not -path './.git/*' \
      -type f 2>/dev/null \
      | while read -r impl_file; do
          REL="${impl_file#./}"
          TARGET_DIR="$SNAP_DIR/impl/$(dirname "$REL")"
          mkdir -p "$TARGET_DIR"
          cp "$impl_file" "$TARGET_DIR/"
        done
  fi

  LABEL=$([ "$KIND" = "pass" ] && echo "COMPLETE" || echo "wip")
  echo "スナップショット保存: $SNAP_DIR (${LABEL})"
  exit 0
fi

# --- git モード ---
if [ "$KIND" = "pass" ]; then
  MSG="feat: ゴール達成 (iter ${ITERATION}) - ${GOAL_SUMMARY}"
else
  VERDICT=$(state_get "last_synthesized_verdict")
  MSG="wip: goal-dual iter ${ITERATION} - ${VERDICT:-incomplete}"
fi
[ -n "$SUFFIX" ] && MSG="${MSG} ${SUFFIX}"

# WIP commit のスキップ判定
# GOAL_DUAL_WIP_COMMITS=0 の場合のみ WIP commit を無効化する（COMPLETE 時は常に commit）
WIP_COMMITS_ENABLED="${GOAL_DUAL_WIP_COMMITS:-1}"
if [ "$KIND" != "pass" ] && [ "$WIP_COMMITS_ENABLED" != "1" ]; then
  echo "WIP commit skipped（GOAL_DUAL_WIP_COMMITS=0）"
  {
    echo ""
    echo "## [$(date)] - WIP commit スキップ (iter ${ITERATION})"
    echo "GOAL_DUAL_WIP_COMMITS=0 のため WIP commit をスキップしました。"
    echo "state と progress.txt は更新済み。"
    echo "---"
  } >> .goal-dual/progress.txt
  exit 0
fi

# .goal-dual/ は gitignore 対象のため commit しない。実装ファイルのみを stage する。
IMPL_UNSTAGED=$(git diff --name-only 2>/dev/null | grep -v '^\.goal-dual/' || true)
IMPL_UNTRACKED=$(git ls-files --others --exclude-standard 2>/dev/null | grep -v '^\.goal-dual/' || true)
[ -n "$IMPL_UNSTAGED" ] && echo "$IMPL_UNSTAGED" | xargs git add
[ -n "$IMPL_UNTRACKED" ] && echo "$IMPL_UNTRACKED" | xargs git add

if git diff --cached --quiet 2>/dev/null; then
  echo "コミット対象なし（変更なし）"
else
  # スコープ違反チェック（advisory モード: 警告のみ、ブロックしない）
  SCOPE_MODE=$(jq -r '.scope_mode // "advisory"' .goal-dual/state.json 2>/dev/null || echo "advisory")
  SCOPE_DENY=$(jq -r '.scope_deny // [] | .[]' .goal-dual/state.json 2>/dev/null || true)
  if [ -n "$SCOPE_DENY" ]; then
    STAGED_FILES=$(git diff --cached --name-only 2>/dev/null || true)
    VIOLATIONS=""
    while IFS= read -r deny_pattern; do
      [ -z "$deny_pattern" ] && continue
      MATCHED=$(echo "$STAGED_FILES" | grep -iF "$deny_pattern" || true)
      [ -n "$MATCHED" ] && VIOLATIONS="${VIOLATIONS}${MATCHED}"$'\n'
    done <<< "$SCOPE_DENY"
    if [ -n "$VIOLATIONS" ]; then
      echo "[scope-warning] 変更範囲外のファイルが含まれています:"
      echo "$VIOLATIONS"
      {
        echo ""
        echo "## [$(date)] - scope-warning (iter ${ITERATION})"
        echo "変更範囲外ファイルを含む commit:"
        echo "$VIOLATIONS"
        echo "scope_mode: $SCOPE_MODE"
        echo "---"
      } >> .goal-dual/progress.txt
    fi
  fi

  git commit -m "$MSG"
  echo "コミット完了: $MSG"
fi
