#!/bin/bash
# goal-dual/scripts/safety.sh — stagnation / 連続 codex_failed 検出
# Usage: bash safety.sh <iteration>
# 終了コード: 0=継続OK / 10=STOP_STAGNANT / 11=STOP_HUMAN
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib.sh"

ITERATION="${1:-1}"
THRESHOLD="${GOAL_DUAL_STAGNATION_THRESHOLD:-3}"
CODEX_FAIL_THRESHOLD=3

# --- 連続 codex_failed チェック ---
CODEX_FAILED_COUNT=$(state_get "codex_failed_count")
CODEX_FAILED_COUNT="${CODEX_FAILED_COUNT:-0}"
if [ "$CODEX_FAILED_COUNT" -ge "$CODEX_FAIL_THRESHOLD" ]; then
  echo "Codex が ${CODEX_FAILED_COUNT} 回連続で失敗しました。人間の介入が必要です。" >&2
  goal_dual_progress "安全弁: STOP_HUMAN（codex_failed 連続 ${CODEX_FAILED_COUNT} 回）" <<EOF
iteration: $ITERATION
codex_failed_count: $CODEX_FAILED_COUNT
EOF
  exit 11
fi

# --- stagnation チェック（lib.sh の consecutive_same_verdict_count に集約）---
COUNT=$(consecutive_same_verdict_count)
if [ "$COUNT" -ge "$THRESHOLD" ]; then
  LATEST=$(ls -t .goal-dual/state/evaluations/synthesized-*.json 2>/dev/null | head -1)
  LAST_VERDICT=$(jq -r '.verdict // "incomplete"' "$LATEST" 2>/dev/null || echo "incomplete")
  echo "stagnation 検出: 直近 ${THRESHOLD} 件の verdict がすべて '${LAST_VERDICT}'" >&2
  goal_dual_progress "安全弁: STOP_STAGNANT（${THRESHOLD} 回連続 ${LAST_VERDICT}）" <<EOF
iteration: $ITERATION
threshold: $THRESHOLD
last_verdict: $LAST_VERDICT
EOF
  exit 10
fi

echo "stagnation チェック: OK"
exit 0
