#!/bin/bash
# goal-dual/scripts/collect-eval-inputs.sh
# 評価エージェント（claude-evaluator / codex-evaluator）が使う入力情報を
# 環境変数エクスポート形式で stdout に出力する。
#
# 呼び出し側:
#   INPUTS_FILE=$(mktemp)
#   bash "$HOME/.claude/goal-dual/scripts/collect-eval-inputs.sh" > "$INPUTS_FILE"
#   source "$INPUTS_FILE"
#   rm -f "$INPUTS_FILE"
#
# 出力変数: GOAL / EVAL_EXIT / EVAL_LOG / DIFF_STAT / DIFF_FILES / ITER
#
# eval 展開は使わない（コマンドインジェクション対策）。
# 値はすべて single-quoted 形式でエスケープして出力する。
set -euo pipefail

# 文字列を single-quoted bash リテラルとして安全にエスケープする
sq_escape() {
  # 入力中の ' を '\'' に置換し、全体を '...' で囲む
  local s="${1-}"
  printf "'%s'" "$(printf '%s' "$s" | sed "s/'/'\\\\''/g")"
}

# --- 入力収集 ---

GOAL_TEXT=$(cat .goal-dual/goal.md 2>/dev/null || echo "")
EVAL_EXIT_VAL=$(cat .goal-dual/state/eval-exit.txt 2>/dev/null || echo "0")
EVAL_LOG_VAL=$(tail -300 .goal-dual/state/eval-output.log 2>/dev/null \
  | grep -E "FAIL|Error|✗|PASS|ok|success|passed" | head -50 \
  || echo "(no eval output)")
ITER_VAL=$(jq -r '.iteration // 0' .goal-dual/state.json 2>/dev/null || echo "0")

NO_GIT=$(jq -r '.no_git // false' .goal-dual/state.json 2>/dev/null || echo "false")
if [ "$NO_GIT" = "true" ]; then
  DIFF_STAT_VAL="(no-git モード: 変更ファイル一覧)"
  if [ -f .goal-dual/.started ]; then
    DIFF_FILES_VAL=$(find . -newer .goal-dual/.started \
      -not -path './.goal-dual/*' \
      -not -path './.git/*' \
      -type f 2>/dev/null | sed 's|^\./||' || echo "")
  else
    DIFF_FILES_VAL="(基準ファイル .goal-dual/.started が存在しない)"
  fi
else
  BASE=$(jq -r '.base_branch // ""' .goal-dual/state.json 2>/dev/null || echo "")
  if [ -n "$BASE" ]; then
    DIFF_STAT_VAL=$(git diff --stat "${BASE}...HEAD" 2>/dev/null | tail -5 || echo "(diff取得失敗)")
    DIFF_FILES_VAL=$(git diff --name-only "${BASE}...HEAD" 2>/dev/null || echo "(ファイル一覧取得失敗)")
  else
    DIFF_STAT_VAL="(base branch 未設定)"
    DIFF_FILES_VAL=""
  fi
fi

# --- single-quoted 形式で出力 ---

printf 'GOAL=%s\n'       "$(sq_escape "$GOAL_TEXT")"
printf 'EVAL_EXIT=%s\n'  "$(sq_escape "$EVAL_EXIT_VAL")"
printf 'EVAL_LOG=%s\n'   "$(sq_escape "$EVAL_LOG_VAL")"
printf 'DIFF_STAT=%s\n'  "$(sq_escape "$DIFF_STAT_VAL")"
printf 'DIFF_FILES=%s\n' "$(sq_escape "$DIFF_FILES_VAL")"
printf 'ITER=%s\n'       "$(sq_escape "$ITER_VAL")"
