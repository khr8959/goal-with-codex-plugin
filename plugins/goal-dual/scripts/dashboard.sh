#!/bin/bash
# goal-dual/scripts/dashboard.sh — ローカル進捗ダッシュボードを起動する
# Usage: bash dashboard.sh [port]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PORT="${1:-${GOAL_DUAL_DASHBOARD_PORT:-3762}}"
HOST="${GOAL_DUAL_DASHBOARD_HOST:-127.0.0.1}"

if ! command -v node >/dev/null 2>&1; then
  echo "Node.js が必要です" >&2
  exit 1
fi

ROOT="$(pwd)"
STATE_FILE=".goal-dual/state/dashboard.json"

if [ "${GOAL_DUAL_DASHBOARD_FORCE:-0}" != "1" ] && [ -f "$STATE_FILE" ] && command -v jq >/dev/null 2>&1; then
  EXISTING_URL=$(jq -r '.url // empty' "$STATE_FILE" 2>/dev/null || true)
  if [ -n "$EXISTING_URL" ] && command -v curl >/dev/null 2>&1; then
    if curl -fsS "${EXISTING_URL}/api/state" >/dev/null 2>&1; then
      echo "goal-dual dashboard は既に起動しています"
      echo "URL: ${EXISTING_URL}"
      echo "再起動する場合: GOAL_DUAL_DASHBOARD_FORCE=1 /goal-dual:dashboard"
      exit 0
    fi
  fi
fi

echo "goal-dual dashboard を起動します"
echo "URL: http://${HOST}:${PORT}（使用中なら自動で次の空きポートへ移動）"
echo "対象: ${ROOT}"
echo ""
echo "停止するには Ctrl-C を押してください。"
echo ""

exec node "$SCRIPT_DIR/dashboard-server.mjs" --host="$HOST" --port="$PORT" --root="$ROOT"
