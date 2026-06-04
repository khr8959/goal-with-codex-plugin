#!/bin/bash
# goal-dual/scripts/status.sh — 現在の Codex 委譲ステップ状態を表示する
set -euo pipefail

STATE=".goal-dual/state.json"
EVIDENCE=".goal-dual/state/evidence-latest.json"

if [ ! -f "$STATE" ]; then
  echo "goal-dual の実行状態はありません。"
  echo "使い方: /goal-dual:run <ゴール>"
  echo "診断  : /goal-dual:doctor"
  exit 0
fi

goal_text=$(jq -r '.goal_text // "(不明)"' "$STATE")
iteration=$(jq -r '.iteration // 0' "$STATE")
completed=$(jq -r '.completed // false' "$STATE")
stop_reason=$(jq -r '.stop_reason // "running"' "$STATE")
phase=$(jq -r '.loop_phase // "awaiting_claude_review"' "$STATE")
branch=$(jq -r '.branch // "(no-git)"' "$STATE")
eval_cmd=$(jq -r '.eval_cmd // "なし"' "$STATE")
last_step=$(jq -r '.last_step_status // "unknown"' "$STATE")

echo "=== goal-dual status ==="
echo ""
echo "Goal       : $(printf '%s' "$goal_text" | tr '\n' ' ' | cut -c1-100)"
echo "Iteration  : $iteration"
echo "Step       : $last_step"
echo "Completed  : $completed"
echo "Reason     : $stop_reason"
echo "Phase      : $phase"
echo "Branch     : $branch"
echo "Eval       : $eval_cmd"

if [ -f "$EVIDENCE" ]; then
  echo ""
  echo "Latest evidence:"
  jq -r '
    "- status : " + (.status // "unknown"),
    "- codex  : " + (.codex.status // "unknown") + " / risk=" + (.codex.risk // "unknown"),
    "- eval   : " + (.eval.label // "unknown"),
    "- files  : " + (((.changed_files // []) | length) | tostring),
    "- next   : " + (.next_action // "なし")
  ' "$EVIDENCE" 2>/dev/null || true
fi

if [ -f .goal-dual/state/scope-violations.txt ]; then
  echo ""
  echo "Scope violation:"
  sed 's/^/  /' .goal-dual/state/scope-violations.txt
fi

echo ""
case "$(jq -r '.status // "unknown"' "$EVIDENCE" 2>/dev/null || echo "unknown")" in
  awaiting_claude_review)
    echo "Next: Claude /goal should review the evidence and decide complete vs another /goal-dual:run."
    ;;
  needs_fix)
    echo "Next: run /goal-dual:run again with no arguments to delegate the next fix step to Codex."
    ;;
  stopped)
    echo "Next: human review is needed before continuing."
    ;;
  *)
    echo "Next: run /goal-dual:run to create the first evidence packet."
    ;;
esac
