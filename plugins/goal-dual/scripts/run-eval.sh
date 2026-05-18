#!/bin/bash
# goal-dual/scripts/run-eval.sh — eval-cmd を実行してログと exit code を保存
# Usage: bash run-eval.sh <iteration>
# 前提: .goal-dual/state.json に eval_cmd が存在すること
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

ITERATION="${1:-0}"
LOG_DIR=".goal-dual/logs"
STATE_DIR=".goal-dual/state"
mkdir -p "$LOG_DIR" "$STATE_DIR"

EVAL_CMD=$(state_get "eval_cmd")
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
LOG_FILE="$LOG_DIR/eval-cmd-${ITERATION}-${TIMESTAMP}.log"

if [ -z "$EVAL_CMD" ] || [ "$EVAL_CMD" = "null" ]; then
  echo "(no eval command configured)" > "$STATE_DIR/eval-output.log"
  echo "0" > "$STATE_DIR/eval-exit.txt"
  echo "eval-cmd: なし（スキップ）"
  exit 0
fi

echo "eval-cmd 実行中: $EVAL_CMD"
EXIT_CODE=0
TIMEOUT_CMD=""
if command -v timeout >/dev/null 2>&1; then
  TIMEOUT_CMD="timeout 600"
elif command -v gtimeout >/dev/null 2>&1; then
  TIMEOUT_CMD="gtimeout 600"
fi
if $TIMEOUT_CMD bash -c "$EVAL_CMD" > "$LOG_FILE" 2>&1; then
  EXIT_CODE=0
else
  EXIT_CODE=$?
fi

# 末尾 500 行をサブエージェント共有用に保存
tail -500 "$LOG_FILE" > "$STATE_DIR/eval-output.log"
echo "$EXIT_CODE" > "$STATE_DIR/eval-exit.txt"

if [ "$EXIT_CODE" -eq 0 ]; then
  echo "eval-cmd: 成功（exit 0）"
else
  echo "eval-cmd: 失敗（exit ${EXIT_CODE}）。ログ: $LOG_FILE"
fi

exit 0
