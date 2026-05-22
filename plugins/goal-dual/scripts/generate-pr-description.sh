#!/bin/bash
# goal-dual/scripts/generate-pr-description.sh
# COMPLETE 時に GitHub PR / changelog 向け説明文を生成し、
# 完了メタ情報（パス・レビュー結果・完了時刻）を state.json に保存する。
# - 説明文: .goal-dual/state/pr-description.md
# - state.json: completed_at / final_review_path / pr_description_path / review_passed / review_result
# 利用例: gh pr create --title "<推奨タイトル>" --body-file .goal-dual/state/pr-description.md
# 注意: archive.sh より前に呼ぶこと（.goal-dual/ が移動する前に state を確定させる）
# exit 0: 成功 / exit 1: Codex 失敗（フォールバック生成済み・state 保存は実施）
set -euo pipefail

SCRIPTS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPTS/lib.sh"

OUTPUT_FILE=".goal-dual/state/pr-description.md"
FINAL_REVIEW_FILE=".goal-dual/state/final-review.md"
mkdir -p "$(dirname "$OUTPUT_FILE")"

CODEX_PLUGIN_ROOT=$(resolve_codex_plugin_root) || true

# --- ゴール本文を抽出（# ゴール 〜 --- の間の本文のみ）---
GOAL=$(awk '/^# ゴール/{f=1;next} /^---/{if(f)exit} f' .goal-dual/goal.md 2>/dev/null \
  | sed '/^[[:space:]]*$/d' || echo "")
[ -z "$GOAL" ] && GOAL=$(jq -r '.goal_text // ""' .goal-dual/state.json 2>/dev/null || echo "")
GOAL_FIRST_LINE=$(printf '%s\n' "$GOAL" | head -1)

ACCEPTANCE=$(cat .goal-dual/state/acceptance-criteria.md 2>/dev/null || echo "(完了条件未設定)")
FINAL_REVIEW=$(head -40 "$FINAL_REVIEW_FILE" 2>/dev/null || echo "(最終レビューなし)")

SYNTH_FILE=$(ls -t .goal-dual/state/evaluations/synthesized-*.json 2>/dev/null | head -1 || true)
SYNTH_REASON=""
if [ -n "$SYNTH_FILE" ]; then
  SYNTH_REASON=$(jq -r '.reason // ""' "$SYNTH_FILE" 2>/dev/null || echo "")
fi

# --- git 情報 ---
NO_GIT=$(jq -r '.no_git // false' .goal-dual/state.json 2>/dev/null || echo "false")
BASE=$(jq -r '.base_branch // ""' .goal-dual/state.json 2>/dev/null || echo "")
BRANCH=$(jq -r '.branch // "(no-git)"' .goal-dual/state.json 2>/dev/null || echo "(no-git)")
ITER=$(jq -r '.iteration // 0' .goal-dual/state.json 2>/dev/null || echo "0")

DIFF_STAT=""
COMMIT_LOG=""
if [ "$NO_GIT" = "false" ] && [ -n "$BASE" ]; then
  DIFF_STAT=$(git diff --stat "${BASE}...HEAD" 2>/dev/null | tail -20 || true)
  COMMIT_LOG=$(git log --pretty='- %s' "${BASE}...HEAD" 2>/dev/null | head -20 || true)
fi
[ -z "$DIFF_STAT" ] && DIFF_STAT="(変更統計なし)"
[ -z "$COMMIT_LOG" ] && COMMIT_LOG="(コミットなし)"

# --- 完了条件をチェックリスト化（達成済みとして [x] を付ける）---
ACCEPTANCE_CHECKLIST=$(printf '%s\n' "$ACCEPTANCE" \
  | awk '/^[[:space:]]*-/ {
      sub(/^[[:space:]]*-[[:space:]]*(\[[ xX]\][[:space:]]*)?/, "")
      print "- [x] " $0
    }')
[ -z "$ACCEPTANCE_CHECKLIST" ] && ACCEPTANCE_CHECKLIST="- [x] 完了条件は acceptance-criteria.md を参照"

# --- 推奨 PR タイトル（先頭行を 70 文字以内に）---
PR_TITLE=$(printf '%s' "$GOAL_FIRST_LINE" | cut -c1-70)
[ -z "$PR_TITLE" ] && PR_TITLE="goal-dual: 自動実装"

# --- Codex で PR 説明文（本文）を生成 ---
PR_BODY=""
if [ -n "${CODEX_PLUGIN_ROOT:-}" ] && [ -f "$CODEX_PLUGIN_ROOT/scripts/codex-companion.mjs" ]; then
  PR_BODY=$(node "$CODEX_PLUGIN_ROOT/scripts/codex-companion.mjs" task \
"以下の情報をもとに、GitHub PR の説明文を日本語で書け。
GitHub にそのまま貼り付けて使えるレベルにし、技術的な変更点を簡潔にまとめること。
推測で書かず、与えられた情報（変更統計・コミット履歴・レビュー要点）に忠実に書くこと。

【ゴール】
${GOAL}

【完了条件】
${ACCEPTANCE}

【最終評価の根拠】
${SYNTH_REASON}

【変更統計】
${DIFF_STAT}

【コミット履歴】
${COMMIT_LOG}

【最終レビューの要点】
${FINAL_REVIEW}

【出力形式（この見出し構造で書け。前後に余計なテキストを付けない）】
## 概要

（このPRが何を解決するかを2〜4行で）

## 変更内容

- （主要な変更点を箇条書きで）

## テスト

- （どう検証したか。完了条件・eval-cmd の結果に基づく）

## レビュー結果

- （最終レビューの結論を1〜2行で）

## レビュアーが確認すべき点

- （マージ前に人間が目視確認すべき点）
" \
  </dev/null 2>/dev/null) || true
fi

# --- ファイル出力 ---
{
  printf '# PR 説明文\n\n'
  printf '> このファイルは goal-dual により自動生成されました。\n'
  printf '> 推奨タイトル: `%s`\n' "$PR_TITLE"
  printf '> 利用例: `gh pr create --title "%s" --body-file %s`\n\n' "$PR_TITLE" "$OUTPUT_FILE"
  printf '%s\n\n' '---'
  if [ -n "$PR_BODY" ] && [ "${#PR_BODY}" -gt 50 ]; then
    printf '%s\n' "$PR_BODY"
  else
    printf '## 概要\n\n'
    printf '%s\n\n' "${GOAL:-（ゴール未取得）}"
    printf '## 変更内容\n\n'
    printf '%s\n\n' "$COMMIT_LOG"
    printf '<details><summary>変更統計</summary>\n\n```\n%s\n```\n\n</details>\n\n' "$DIFF_STAT"
    printf '## テスト\n\n'
    printf '%s\n\n' "$ACCEPTANCE_CHECKLIST"
    printf '## レビュー結果\n\n'
    printf '%s\n\n' "${SYNTH_REASON:-（合議評価で complete 判定）}"
    printf '## レビュアーが確認すべき点\n\n'
    printf '%s\n' '- マージ前に動作を手動で確認する'
    printf '%s\n' '- 詳細は最終レビュー（final-review.md）を参照'
  fi
} > "$OUTPUT_FILE"

echo "pr-description.md を生成しました: $OUTPUT_FILE"

# --- 完了メタ情報を state.json に保存（archive で移動しても有効な相対パスで保存）---
COMPLETED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)
PR_REL="state/pr-description.md"
REVIEW_REL=""
[ -f "$FINAL_REVIEW_FILE" ] && REVIEW_REL="state/final-review.md"

# レビュー通過結果を判定（COMPLETE に到達した時点で原則 pass。final-review の最終判定で上書き）
REVIEW_PASSED=true
REVIEW_RESULT="pass: コードレビュー完了"
if [ -f "$FINAL_REVIEW_FILE" ]; then
  if grep -qiE 'STOP_HUMAN|verdict:[[:space:]]*fail|Critical:[[:space:]]*(あり|yes|true|[1-9])' "$FINAL_REVIEW_FILE" 2>/dev/null; then
    REVIEW_PASSED=false
    REVIEW_RESULT="critical: final-review.md に重大指摘あり"
  fi
fi

state_set "completed_at" "$COMPLETED_AT"
state_set "pr_description_path" "$PR_REL"
[ -n "$REVIEW_REL" ] && state_set "final_review_path" "$REVIEW_REL"
state_set "review_passed" "$REVIEW_PASSED"
state_set "review_result" "$REVIEW_RESULT"

echo "state.json に完了情報を保存しました（completed_at / pr_description_path / final_review_path / review_passed / review_result）"
