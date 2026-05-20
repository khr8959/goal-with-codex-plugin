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

GOAL_DUAL_FILES=()
[ -f .goal-dual/progress.txt ]    && GOAL_DUAL_FILES+=(.goal-dual/progress.txt)
[ -f .goal-dual/goal.md ]         && GOAL_DUAL_FILES+=(.goal-dual/goal.md)
[ -f .goal-dual/state.json ]      && GOAL_DUAL_FILES+=(.goal-dual/state.json)

SYNTH_FILES=$(find .goal-dual/state/evaluations -name "synthesized-*.json" 2>/dev/null || true)

if [ "$KIND" = "pass" ] && [ -f .goal-dual/state/final-review.md ]; then
  GOAL_DUAL_FILES+=(.goal-dual/state/final-review.md)
fi

[ "${#GOAL_DUAL_FILES[@]}" -gt 0 ] && git add -f "${GOAL_DUAL_FILES[@]}"
[ -n "$SYNTH_FILES" ] && echo "$SYNTH_FILES" | xargs git add

IMPL_UNSTAGED=$(git diff --name-only 2>/dev/null | grep -v '^\.goal-dual/' || true)
[ -n "$IMPL_UNSTAGED" ] && echo "$IMPL_UNSTAGED" | xargs git add

if git diff --cached --quiet 2>/dev/null; then
  echo "コミット対象なし（変更なし）"
else
  git commit -m "$MSG"
  echo "コミット完了: $MSG"
fi
