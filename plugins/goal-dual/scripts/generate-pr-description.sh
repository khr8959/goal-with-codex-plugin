#!/bin/bash
# goal-dual/scripts/generate-pr-description.sh
# COMPLETE 時に GitHub PR / changelog 向け説明文を生成する
# .goal-dual/state/pr-description.md に保存する
# 将来的に: gh pr create --body-file .goal-dual/state/pr-description.md
# exit 0: 成功 / exit 1: Codex 失敗（フォールバック生成済み）
set -euo pipefail

SCRIPTS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPTS/lib.sh"

OUTPUT_FILE=".goal-dual/state/pr-description.md"
mkdir -p "$(dirname "$OUTPUT_FILE")"

CODEX_PLUGIN_ROOT=$(resolve_codex_plugin_root) || true

GOAL=$(cat .goal-dual/goal.md 2>/dev/null | grep -v '^---' | grep -v '^設定日' | grep -v '^モード' | grep -v '^review' || echo "")
ACCEPTANCE=$(cat .goal-dual/state/acceptance-criteria.md 2>/dev/null || echo "(完了条件未設定)")
FINAL_REVIEW=$(cat .goal-dual/state/final-review.md 2>/dev/null | head -30 || echo "(最終レビューなし)")

SYNTH_FILE=$(ls -t .goal-dual/state/evaluations/synthesized-*.json 2>/dev/null | head -1 || true)
SYNTH_REASON=""
if [ -n "$SYNTH_FILE" ]; then
  SYNTH_REASON=$(jq -r '.reason // ""' "$SYNTH_FILE" 2>/dev/null || echo "")
fi

# git diff stat と commit log
DIFF_STAT=""
COMMIT_LOG=""
NO_GIT=$(jq -r '.no_git // false' .goal-dual/state.json 2>/dev/null || echo "false")
BASE=$(jq -r '.base_branch // ""' .goal-dual/state.json 2>/dev/null || echo "")
BRANCH=$(jq -r '.branch // "(no-git)"' .goal-dual/state.json 2>/dev/null || echo "(no-git)")

if [ "$NO_GIT" = "false" ] && [ -n "$BASE" ]; then
  DIFF_STAT=$(git diff --stat "${BASE}...HEAD" 2>/dev/null | tail -5 || echo "(変更なし)")
  COMMIT_LOG=$(git log --oneline "${BASE}...HEAD" 2>/dev/null | head -10 || echo "(コミットなし)")
fi

# Codex で PR 説明文を生成
PR_BODY=""
if [ -n "${CODEX_PLUGIN_ROOT:-}" ] && [ -f "$CODEX_PLUGIN_ROOT/scripts/codex-companion.mjs" ]; then
  PR_BODY=$(node "$CODEX_PLUGIN_ROOT/scripts/codex-companion.mjs" task \
"以下の情報をもとに、GitHub PR の説明文を英語で書け。
技術的な変更点を簡潔にまとめ、GitHub に貼り付けてそのまま使えるレベルにする。

【ゴール】
${GOAL}

【完了条件】
${ACCEPTANCE}

【最終評価】
${SYNTH_REASON}

【変更統計】
${DIFF_STAT}

【コミット履歴】
${COMMIT_LOG}

【最終レビューの要点】
${FINAL_REVIEW}

【出力形式（この構造で書け、前後にテキスト不可）】
## Summary

-

## Changes

-

## Test

-

## Review Notes

-

## Human Check

-
" \
  </dev/null 2>&1) || true
fi

{
  printf '# PR 説明文\n\n'
  printf '> このファイルは自動生成されました。\n'
  printf '> `gh pr create --body-file .goal-dual/state/pr-description.md` で利用できます。\n\n'
  printf '---\n\n'
  if [ -n "$PR_BODY" ] && [ "${#PR_BODY}" -gt 50 ]; then
    echo "$PR_BODY"
  else
    printf '## Summary\n\n'
    printf '- %s\n\n' "$(echo "$GOAL" | grep -v '^#' | head -1 | tr -d '\n')"
    printf '## Changes\n\n'
    printf '%s\n\n' "${DIFF_STAT:-（変更統計取得不可）}"
    printf '## Test\n\n'
    printf '- See acceptance criteria in .goal-dual/state/acceptance-criteria.md\n\n'
    printf '## Review Notes\n\n'
    printf '%s\n\n' "${SYNTH_REASON:-（評価なし）}"
    printf '## Human Check\n\n'
    printf '- Verify the behavior manually before merging\n'
  fi
} > "$OUTPUT_FILE"

echo "pr-description.md を生成しました: $OUTPUT_FILE"
