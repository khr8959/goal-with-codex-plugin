#!/bin/bash
# goal-dual/scripts/safety.sh — stagnation / 連続 codex_failed 検出 / Codex Work 停止条件
# Usage: bash safety.sh <iteration>
# 終了コード: 0=継続OK / 10=STOP_STAGNANT / 11=STOP_HUMAN
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib.sh"

ITERATION="${1:-1}"
THRESHOLD="${GOAL_DUAL_STAGNATION_THRESHOLD:-3}"
CODEX_FAIL_THRESHOLD=3
CODEX_WORK_RESULT=".goal-dual/codex-work-result.json"
NO_CHANGE_THRESHOLD=3

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

# --- Codex Work 停止条件チェック ---
if [ -f "$CODEX_WORK_RESULT" ]; then
  CODEX_WORK_STATUS=$(jq -r '.status // ""' "$CODEX_WORK_RESULT" 2>/dev/null || echo "")
  CODEX_WORK_RISK=$(jq -r '.risk // ""' "$CODEX_WORK_RESULT" 2>/dev/null || echo "")

  # 停止条件1: status が "blocked" の場合 → STOP_HUMAN
  if [ "$CODEX_WORK_STATUS" = "blocked" ]; then
    echo "Codex Work の status が blocked です。人間の介入が必要です。" >&2
    goal_dual_progress "安全弁: STOP_HUMAN（codex-work-result.json の status=blocked）" <<EOF
iteration: $ITERATION
codex_work_status: $CODEX_WORK_STATUS
EOF
    exit 11
  fi

  # 停止条件3: risk が "high" の場合 → 既定 STOP_HUMAN。
  # GOAL_DUAL_ALLOW_HIGH_RISK=1 のときだけ候補フラグに留める。
  if [ "$CODEX_WORK_RISK" = "high" ]; then
    if [ "${GOAL_DUAL_ALLOW_HIGH_RISK:-0}" != "1" ]; then
      echo "Codex Work の risk が high です。人間の確認が必要です。" >&2
      goal_dual_progress "安全弁: STOP_HUMAN（codex-work-result.json の risk=high）" <<EOF
iteration: $ITERATION
codex_work_risk: $CODEX_WORK_RISK
EOF
      goal_dual_event "stopped_high_risk" "$(jq -nc --argjson iteration "$ITERATION" '{iteration:$iteration,reason:"risk_high"}')"
      exit 11
    fi
    echo "[STOP_HUMAN_CANDIDATE] Codex Work の risk が high です（GOAL_DUAL_ALLOW_HIGH_RISK=1 のため続行候補）。" >&2
    goal_dual_progress "警告: STOP_HUMAN 候補（codex-work-result.json の risk=high、明示許可あり）" <<EOF
iteration: $ITERATION
codex_work_risk: $CODEX_WORK_RISK
EOF
    touch .goal-dual/STOP_HUMAN_CANDIDATE 2>/dev/null || true
  fi

  # 停止条件2: status が "no_change" の場合のカウント更新
  if [ "$CODEX_WORK_STATUS" = "no_change" ]; then
    CURRENT_NO_CHANGE=$(state_get "codex_work_no_change_count")
    CURRENT_NO_CHANGE="${CURRENT_NO_CHANGE:-0}"
    NEW_NO_CHANGE=$(( CURRENT_NO_CHANGE + 1 ))
    state_set "codex_work_no_change_count" "$NEW_NO_CHANGE"
    echo "Codex Work の status が no_change です（連続 ${NEW_NO_CHANGE} 回）。" >&2

    if [ "$NEW_NO_CHANGE" -ge "$NO_CHANGE_THRESHOLD" ]; then
      echo "Codex Work が ${NEW_NO_CHANGE} 回連続で no_change です。stagnation と判定します。" >&2
      goal_dual_progress "安全弁: STOP_STAGNANT（codex-work-result.json の status=no_change 連続 ${NEW_NO_CHANGE} 回）" <<EOF
iteration: $ITERATION
codex_work_no_change_count: $NEW_NO_CHANGE
EOF
      exit 10
    fi
  else
    # no_change 以外なら連続カウントをリセット
    state_set "codex_work_no_change_count" "0"
  fi
fi

# --- 同じ eval-output.log の内容が2回続いた場合のチェック ---
EVAL_LOG=".goal-dual/state/eval-output.log"
if [ -f "$EVAL_LOG" ]; then
  CURRENT_EVAL_HASH=$(md5sum "$EVAL_LOG" 2>/dev/null | awk '{print $1}' || echo "")
  if [ -n "$CURRENT_EVAL_HASH" ]; then
    PREV_EVAL_HASH=$(state_get "last_eval_output_hash")
    if [ -n "$PREV_EVAL_HASH" ] && [ "$CURRENT_EVAL_HASH" = "$PREV_EVAL_HASH" ]; then
      echo "[STOP_STAGNANT_CANDIDATE] eval-output.log の内容が前回と同一です。" >&2
      goal_dual_progress "警告: STOP_STAGNANT 候補（eval-output.log が前回と同一）" <<EOF
iteration: $ITERATION
eval_output_hash: $CURRENT_EVAL_HASH
EOF
    fi
    state_set "last_eval_output_hash" "$CURRENT_EVAL_HASH"
  fi
fi

# --- stagnation チェック（lib.sh の consecutive_same_verdict_count に集約）---
COUNT=$(consecutive_same_verdict_count)
if [ "$COUNT" -ge "$THRESHOLD" ]; then
  LATEST=$(find .goal-dual/state/evaluations -name "synthesized-*.json" 2>/dev/null \
    | sed -E 's/.*synthesized-([0-9]+)\.json$/\1 &/' \
    | sort -rn \
    | awk 'NR == 1 {print $2}')
  LAST_VERDICT=$(jq -r '.verdict // "incomplete"' "$LATEST" 2>/dev/null || echo "incomplete")
  echo "stagnation 検出: 直近 ${THRESHOLD} 件の verdict がすべて '${LAST_VERDICT}'" >&2
  goal_dual_progress "安全弁: STOP_STAGNANT（${THRESHOLD} 回連続 ${LAST_VERDICT}）" <<EOF
iteration: $ITERATION
threshold: $THRESHOLD
last_verdict: $LAST_VERDICT
EOF
  exit 10
fi

if [ "$THRESHOLD" -gt 1 ] && [ "$COUNT" -eq $(( THRESHOLD - 1 )) ]; then
  LATEST=$(find .goal-dual/state/evaluations -name "synthesized-*.json" 2>/dev/null \
    | sed -E 's/.*synthesized-([0-9]+)\.json$/\1 &/' \
    | sort -rn \
    | awk 'NR == 1 {print $2}')
  LAST_VERDICT=$(jq -r '.verdict // "incomplete"' "$LATEST" 2>/dev/null || echo "incomplete")
  state_set "pivot_requested" "true"
  echo "[STOP_STAGNANT_CANDIDATE] ${LAST_VERDICT} が ${COUNT} 回連続しています。次回 Codex Work に別アプローチを要求します。" >&2
  goal_dual_progress "警告: STOP_STAGNANT 候補（${COUNT} 回連続 ${LAST_VERDICT}、次回 pivot 要求）" <<EOF
iteration: $ITERATION
threshold: $THRESHOLD
count: $COUNT
last_verdict: $LAST_VERDICT
pivot_requested: true
EOF
fi

echo "stagnation チェック: OK"
exit 0
