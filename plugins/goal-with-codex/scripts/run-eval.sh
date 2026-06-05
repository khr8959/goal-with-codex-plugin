#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/eval-registry.sh"

ITERATION="${1:-0}"
mkdir -p "$GWC_DIR/logs" "$GWC_DIR/state"

EVAL_CMD=$(gwc_state_get eval_cmd)
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
LOG_FILE="$GWC_DIR/logs/eval-${ITERATION}-${TIMESTAMP}.log"

if [ -z "$EVAL_CMD" ] || [ "$EVAL_CMD" = "null" ]; then
  echo "(no eval command configured)" > "$GWC_DIR/state/eval-output.log"
  echo "" > "$GWC_DIR/state/eval-exit.txt"
  echo "eval: skipped"
  exit 0
fi

EXIT_CODE=0
if gwc_run_allowed_eval "$EVAL_CMD" > "$LOG_FILE" 2>&1; then
  EXIT_CODE=0
else
  EXIT_CODE=$?
fi

tail -500 "$LOG_FILE" | gwc_redact_for_llm > "$GWC_DIR/state/eval-output.log"
echo "$EXIT_CODE" > "$GWC_DIR/state/eval-exit.txt"

if [ "$EXIT_CODE" -eq 0 ]; then
  echo "eval: passed ($EVAL_CMD)"
else
  echo "eval: failed exit=$EXIT_CODE ($EVAL_CMD)"
fi
