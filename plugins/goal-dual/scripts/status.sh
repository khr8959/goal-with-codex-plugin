#!/bin/bash
# goal-dual/scripts/status.sh — 現在の run 状態を人間向けに表示する
set -euo pipefail

STATE=".goal-dual/state.json"

if [ ! -f "$STATE" ]; then
  echo "goal-dual の実行状態はありません。"
  echo "計画から始める場合: /goal-dual:plan <相談したいゴール>"
  echo "直接実行する場合: /goal-dual:run <ゴール>"
  exit 0
fi

goal_text=$(jq -r '.goal_text // "(不明)"' "$STATE")
iteration=$(jq -r '.iteration // 0' "$STATE")
completed=$(jq -r '.completed // false' "$STATE")
stop_reason=$(jq -r '.stop_reason // "running"' "$STATE")
phase=$(jq -r '.loop_phase // "iterating"' "$STATE")
branch=$(jq -r '.branch // "(no-git)"' "$STATE")
eval_cmd=$(jq -r '.eval_cmd // "なし"' "$STATE")
scope_mode=$(jq -r '.scope_mode // "enforce"' "$STATE")
review_level=$(jq -r '.review_level // "standard"' "$STATE")

echo "=== goal-dual status ==="
echo ""
echo "Goal       : $(printf '%s' "$goal_text" | tr '\n' ' ' | cut -c1-100)"
echo "Iteration  : $iteration"
echo "Completed  : $completed"
echo "Reason     : $stop_reason"
echo "Phase      : $phase"
echo "Branch     : $branch"
echo "Eval       : $eval_cmd"
echo "Scope mode : $scope_mode"
echo "Review     : $review_level"

latest_synth=$(find .goal-dual/state/evaluations -name "synthesized-*.json" 2>/dev/null \
  | sed -E 's/.*synthesized-([0-9]+)\.json$/\1 &/' \
  | sort -rn \
  | awk 'NR == 1 {print $2}')

if [ -n "${latest_synth:-}" ] && [ -f "$latest_synth" ]; then
  echo ""
  echo "Latest verdict:"
  jq -r '
    "- verdict: " + (.verdict // "unknown"),
    "- reason : " + (.reason // "unknown"),
    "- next   : " + ((.next_action // "なし") | tostring)
  ' "$latest_synth" 2>/dev/null || true
fi

if [ -f .goal-dual/state/scope-violations.txt ]; then
  echo ""
  echo "Scope violation:"
  sed 's/^/  /' .goal-dual/state/scope-violations.txt
fi

if [ "$completed" = "true" ] && [ "$stop_reason" != "COMPLETE" ]; then
  echo ""
  echo "次の確認:"
  echo "  /goal-dual:explain-stop"
elif [ "$completed" = "true" ]; then
  echo ""
  echo "次の確認:"
  echo "  final-report.md と差分を確認してください。既定では commit は作成されません。"
fi
