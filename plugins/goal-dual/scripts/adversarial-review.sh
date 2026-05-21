#!/bin/bash
# goal-dual/scripts/adversarial-review.sh
# mini-plan.md を Codex で批判的レビューし plan-revised.md を保存する
# exit 0: 成功 / exit 1: 失敗（codex_failed 相当）
set -euo pipefail

SCRIPTS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPTS/lib.sh"

PLUGIN_ROOT=$(resolve_plugin_root) || exit 1
MINI_PLAN=$(cat .goal-dual/state/mini-plan.md)
ITER=$(jq -r '.iteration' .goal-dual/state.json)
LOG_FILE=".goal-dual/logs/codex-adversarial-${ITER}-$(date +%Y%m%d-%H%M%S).log"
mkdir -p .goal-dual/logs

OUTPUT=$(node "$PLUGIN_ROOT/scripts/codex-companion.mjs" task \
  "次の実装計画を批判的に評価し、改訂版を返せ。

【評価の観点】
- 隠れたリスク・エッジケース・副作用
- 既存コードとの整合性
- より単純な代替実装がないか
- テスト方針の妥当性

【出力形式】
まず「## 批判的指摘」に問題点を箇条書き、続いて「## 改訂版計画」に指摘を踏まえた修正済み計画を出力せよ。

## 評価対象の計画
${MINI_PLAN}" </dev/null 2>&1) || true

echo "$OUTPUT" > "$LOG_FILE"

if [ -z "$OUTPUT" ] || [ "${#OUTPUT}" -lt 50 ]; then
  exit 1
fi

echo "$OUTPUT" > .goal-dual/state/plan-revised.md
