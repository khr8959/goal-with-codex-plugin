#!/bin/bash
# goal-dual/scripts/adversarial-review.sh
# Codex Work の結果（codex-work-result.json と差分）を批判的レビューし plan-revised.md を保存する
# exit 0: 成功 / exit 1: 失敗（codex_failed 相当）
#
# [新ループ対応] mini-plan.md は Claude Plan を外したため生成されない。
# 代わりに codex-work-result.json と git diff --stat をレビュー対象とする。
set -euo pipefail

SCRIPTS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPTS/lib.sh"

CODEX_PLUGIN_ROOT=$(resolve_codex_plugin_root) || exit 1
ITER=$(jq -r '.iteration' .goal-dual/state.json)
LOG_FILE=".goal-dual/logs/codex-adversarial-${ITER}-$(date +%Y%m%d-%H%M%S).log"
mkdir -p .goal-dual/logs

# Codex Work の結果を読む（新ループ）。なければ mini-plan.md にフォールバック（旧ループ互換）
if [ -f ".goal-dual/codex-work-result.json" ]; then
  REVIEW_TARGET=$(cat .goal-dual/codex-work-result.json)
  DIFF_STAT=$(git diff --stat HEAD 2>/dev/null || true)
  REVIEW_SOURCE="codex-work-result.json + git diff"
elif [ -f ".goal-dual/state/mini-plan.md" ]; then
  REVIEW_TARGET=$(cat .goal-dual/state/mini-plan.md)
  DIFF_STAT=""
  REVIEW_SOURCE="mini-plan.md（旧ループ互換）"
else
  echo "[adversarial-review] レビュー対象が見つかりません（codex-work-result.json も mini-plan.md もなし）" >> "$LOG_FILE"
  exit 1
fi

OUTPUT=$(node "$CODEX_PLUGIN_ROOT/scripts/codex-companion.mjs" task \
  "次の実装内容を批判的に評価し、改訂版の方針を返せ。

【評価の観点】
- 隠れたリスク・エッジケース・副作用
- 既存コードとの整合性
- より単純な代替実装がないか
- テスト方針の妥当性

【出力形式】
まず「## 批判的指摘」に問題点を箇条書き、続いて「## 改訂版方針」に指摘を踏まえた修正方針を出力せよ。

## レビュー対象（${REVIEW_SOURCE}）
${REVIEW_TARGET}

## 変更差分統計
${DIFF_STAT:-（差分情報なし）}" </dev/null 2>&1) || true

echo "$OUTPUT" > "$LOG_FILE"

if [ -z "$OUTPUT" ] || [ "${#OUTPUT}" -lt 50 ]; then
  exit 1
fi

echo "$OUTPUT" > .goal-dual/state/plan-revised.md
