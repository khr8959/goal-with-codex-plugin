#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PORT="${1:-${GOAL_WITH_CODEX_DASHBOARD_PORT:-3762}}"
HOST="${GOAL_WITH_CODEX_DASHBOARD_HOST:-127.0.0.1}"
STATE_FILE=".goal-with-codex/state/dashboard.json"

mkdir -p ".goal-with-codex/state" ".goal-with-codex/logs"

if [ "${GOAL_WITH_CODEX_DASHBOARD_FORCE:-0}" != "1" ] && [ -f "$STATE_FILE" ] && command -v jq >/dev/null 2>&1; then
  old_pid=$(jq -r '.pid // empty' "$STATE_FILE" 2>/dev/null || true)
  old_url=$(jq -r '.url // empty' "$STATE_FILE" 2>/dev/null || true)
  if [ -n "$old_pid" ] && kill -0 "$old_pid" 2>/dev/null; then
    echo "goal-with-codex dashboard is already running"
    echo "$old_url"
    echo "Restart with: GOAL_WITH_CODEX_DASHBOARD_FORCE=1 /goal-with-codex:dashboard"
    exit 0
  fi
fi

nohup node "$SCRIPT_DIR/dashboard-server.mjs" --host="$HOST" --port="$PORT" > ".goal-with-codex/logs/dashboard.log" 2>&1 &

for _ in 1 2 3 4 5; do
  if [ -f "$STATE_FILE" ] && command -v jq >/dev/null 2>&1; then
    jq -r '.url' "$STATE_FILE"
    exit 0
  fi
  sleep 0.4
done

echo "http://$HOST:$PORT"
