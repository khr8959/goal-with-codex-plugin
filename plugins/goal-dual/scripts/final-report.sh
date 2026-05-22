#!/bin/bash
# goal-dual/scripts/final-report.sh
# 完了・停止時に人間向けレポートを .goal-dual/state/final-report.md に生成する
# Usage: bash final-report.sh [stop-reason]
# stop-reason: COMPLETE | STOP_HUMAN | STOP_STAGNANT | STOP_DIRTY
set -euo pipefail

SCRIPTS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPTS/lib.sh"

STOP_REASON="${1:-$(jq -r '.stop_reason // "UNKNOWN"' .goal-dual/state.json 2>/dev/null)}"
OUTPUT_FILE=".goal-dual/state/final-report.md"
CODEX_PLUGIN_ROOT=$(resolve_codex_plugin_root) || true

GOAL=$(cat .goal-dual/goal.md 2>/dev/null || echo "(ゴール未取得)")
ACCEPTANCE=$(cat .goal-dual/state/acceptance-criteria.md 2>/dev/null || echo "(完了条件未設定)")
ITER=$(jq -r '.iteration // 0' .goal-dual/state.json 2>/dev/null || echo "0")
BRANCH=$(jq -r '.branch // "(no-git)"' .goal-dual/state.json 2>/dev/null || echo "(no-git)")
NO_GIT=$(jq -r '.no_git // false' .goal-dual/state.json 2>/dev/null || echo "false")
FINAL_REVIEW=$(cat .goal-dual/state/final-review.md 2>/dev/null | head -50 || echo "(最終レビューなし)")

# 最新の synthesized verdict を取得
SYNTH_FILE=$(ls -t .goal-dual/state/evaluations/synthesized-*.json 2>/dev/null | head -1 || true)
if [ -n "$SYNTH_FILE" ]; then
  VERDICT=$(jq -r '.verdict // "不明"' "$SYNTH_FILE" 2>/dev/null || echo "不明")
  SYNTH_REASON=$(jq -r '.reason // ""' "$SYNTH_FILE" 2>/dev/null || echo "")
  NEXT_ACTION=$(jq -r '.next_action // ""' "$SYNTH_FILE" 2>/dev/null || echo "")
else
  VERDICT="不明"
  SYNTH_REASON=""
  NEXT_ACTION=""
fi

# git diff stat（git モードのみ）
DIFF_STAT=""
BASE=$(jq -r '.base_branch // ""' .goal-dual/state.json 2>/dev/null || echo "")
if [ "$NO_GIT" = "false" ] && [ -n "$BASE" ]; then
  DIFF_STAT=$(git diff --stat "${BASE}...HEAD" 2>/dev/null | tail -3 || echo "(変更なし)")
fi

# eval ログ（最新 20 行の要点のみ）
EVAL_LOG=$(grep -E "FAIL|Error|✗|PASS|ok|success|passed" \
  .goal-dual/state/eval-output.log 2>/dev/null | tail -20 || echo "(テストログなし)")

# Codex でレポート本文を生成する（失敗時はシンプルテンプレートで代替）
REPORT_BODY=""
if [ -n "${CODEX_PLUGIN_ROOT:-}" ] && [ -f "$CODEX_PLUGIN_ROOT/scripts/codex-companion.mjs" ]; then
  REPORT_BODY=$(node "$CODEX_PLUGIN_ROOT/scripts/codex-companion.mjs" task \
"以下の情報をもとに、非エンジニアにも分かるゴール達成レポートを日本語で書け。
専門用語を避け、平易な言葉で書くこと。

【ゴール】
${GOAL}

【完了条件】
${ACCEPTANCE}

【停止理由】
${STOP_REASON}（イテレーション数: ${ITER}）

【最終評価結果】
verdict: ${VERDICT}
${SYNTH_REASON}

【変更統計】
${DIFF_STAT}

【最終レビューの要点（先頭 50 行）】
${FINAL_REVIEW}

【テスト結果の要点】
${EVAL_LOG}

【出力形式（この構造で書け、前後にテキスト不可）】
## 実装したこと

（変更した機能・ファイルを非エンジニア向けに 2〜5 行で）

## 確認結果

（テストやレビューの結果を 1〜3 行で）

## 残っている注意点

（未対応項目や警告があれば 1〜3 行。なければ「特になし」）

## 人間が確認するとよいこと

（動作確認や目視確認が必要な点を 1〜3 行）

## 次にやるとよいこと

（改善案や次のステップを 1〜3 行。停止した場合は再開手順も）" \
  </dev/null 2>&1) || true
fi

mkdir -p "$(dirname "$OUTPUT_FILE")"

{
  echo "# goal-dual 完了レポート"
  echo ""
  echo "**停止理由:** ${STOP_REASON}"
  echo "**ゴール:** $(echo "$GOAL" | head -3 | grep -v '^#' | head -1)"
  echo "**イテレーション数:** ${ITER}"
  echo "**最終評価:** ${VERDICT}"
  if [ "$NO_GIT" = "false" ]; then
    echo "**ブランチ:** ${BRANCH}"
  fi
  echo "**生成日時:** $(date)"
  echo ""
  echo "---"
  echo ""
  echo "## ゴール"
  echo ""
  echo "$GOAL" | grep -v '^---' | grep -v '^設定日' | grep -v '^モード' | grep -v '^review' | head -10
  echo ""
  echo "## 完了条件"
  echo ""
  echo "$ACCEPTANCE"
  echo ""
  if [ -n "$REPORT_BODY" ] && [ "${#REPORT_BODY}" -gt 50 ]; then
    echo "$REPORT_BODY"
  else
    echo "## 実装したこと"
    echo ""
    if [ -n "$DIFF_STAT" ]; then
      echo "$DIFF_STAT"
    else
      echo "（変更内容の詳細は .goal-dual/state/final-review.md を参照）"
    fi
    echo ""
    echo "## 確認結果"
    echo ""
    echo "最終評価: ${VERDICT}"
    [ -n "$SYNTH_REASON" ] && echo "$SYNTH_REASON"
    echo ""
    echo "## 残っている注意点"
    echo ""
    [ -n "$NEXT_ACTION" ] && echo "$NEXT_ACTION" || echo "特になし"
    echo ""
    echo "## 人間が確認するとよいこと"
    echo ""
    echo "- final-review.md の内容を確認する"
    echo ""
    echo "## 次にやるとよいこと"
    echo ""
    case "$STOP_REASON" in
      COMPLETE)
        echo "- \`git push -u origin ${BRANCH} && gh pr create\` で PR を作成する"
        ;;
      STOP_HUMAN)
        echo "- .goal-dual/progress.txt と final-review.md を確認して対処する"
        echo "- 対処後、同じ /goal-dual コマンドで再開できる"
        ;;
      STOP_STAGNANT)
        echo "- ゴールをより具体的に書き直して再度 /goal-dual を実行する"
        echo "- .goal-dual/state/evaluations/ の synthesized JSON を参照して詰まった原因を確認する"
        ;;
      *)
        echo "- .goal-dual/progress.txt を確認する"
        ;;
    esac
  fi
} > "$OUTPUT_FILE"

echo "final-report.md を生成しました: $OUTPUT_FILE"
