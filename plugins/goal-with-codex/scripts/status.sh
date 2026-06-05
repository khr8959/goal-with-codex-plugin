#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib.sh"

if [ ! -f "$GWC_STATE" ]; then
  echo "goal-with-codex: no active goal"
  echo "Start with: /goal-with-codex:run <goal>"
  exit 0
fi

echo "goal-with-codex status"
echo
jq -r '
  "Goal: " + (.technical_goal // .user_goal // "(unknown)") + "\n" +
  "Iteration: " + ((.iteration // 0)|tostring) + "\n" +
  "Phase: " + (.loop_phase // "unknown") + "\n" +
  "Eval: " + ((.eval_cmd // "") | if . == "" then "none" else . end) + "\n" +
  "Last action: " + ((.last_action // "") | if . == "" then "none" else . end)
' "$GWC_STATE"

if [ -f "$GWC_DIR/state/evidence-latest.json" ]; then
  echo
  echo "Latest evidence:"
  jq '{status,recommendation,trigger,codex_action,eval,changed_files,next_commands}' "$GWC_DIR/state/evidence-latest.json"
else
  echo
  echo "No evidence yet."
fi
