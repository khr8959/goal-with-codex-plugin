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

run_with_timeout() {
  if command -v timeout >/dev/null 2>&1; then
    timeout 600 "$@"
  elif command -v gtimeout >/dev/null 2>&1; then
    gtimeout 600 "$@"
  else
    "$@"
  fi
}

run_allowed_eval() {
  case "$EVAL_CMD" in
    "npm test") run_with_timeout npm test ;;
    "npm run test") run_with_timeout npm run test ;;
    "pnpm test") run_with_timeout pnpm test ;;
    "pnpm run test") run_with_timeout pnpm run test ;;
    "yarn test") run_with_timeout yarn test ;;
    "bun test") run_with_timeout bun test ;;
    "pytest") run_with_timeout pytest ;;
    "python -m pytest") run_with_timeout python -m pytest ;;
    "python3 -m pytest") run_with_timeout python3 -m pytest ;;
    "go test ./...") run_with_timeout go test ./... ;;
    "cargo test") run_with_timeout cargo test ;;
    "dotnet test") run_with_timeout dotnet test ;;
    "gradle test") run_with_timeout gradle test ;;
    "./gradlew test") run_with_timeout ./gradlew test ;;
    "mvn test") run_with_timeout mvn test ;;
    "./mvnw test") run_with_timeout ./mvnw test ;;
    "make test") run_with_timeout make test ;;
    *)
      echo "eval-cmd は許可されていないため実行しませんでした: $EVAL_CMD"
      echo "許可されるコマンド: npm test, npm run test, pnpm test, pnpm run test, yarn test, bun test, pytest, python -m pytest, python3 -m pytest, go test ./..., cargo test, dotnet test, gradle test, ./gradlew test, mvn test, ./mvnw test, make test"
      return 126
      ;;
  esac
}

if run_allowed_eval > "$LOG_FILE" 2>&1; then
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
