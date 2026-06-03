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
echo "goal-dual dashboard を起動します"
echo "URL: http://${HOST}:${PORT}"
echo "対象: ${ROOT}"
echo ""
echo "停止するには Ctrl-C を押してください。"
echo ""

exec node "$SCRIPT_DIR/dashboard-server.mjs" --host="$HOST" --port="$PORT" --root="$ROOT"
