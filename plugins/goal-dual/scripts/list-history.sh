#!/bin/bash
# goal-dual/scripts/list-history.sh — .goal-dual-archive/ の一覧表示
# Usage: bash list-history.sh
set -euo pipefail

ARCHIVE_ROOT=".goal-dual-archive"

if [ ! -d "$ARCHIVE_ROOT" ]; then
  echo "アーカイブがありません（${ARCHIVE_ROOT}/ が存在しない）"
  exit 0
fi

# 日時降順（find | sort -r で移植性を確保）
ENTRIES=$(find "$ARCHIVE_ROOT" -mindepth 1 -maxdepth 1 -type d \
  | grep -E '/[0-9]{8}-[0-9]{6}-' | sort -r || true)

if [ -z "$ENTRIES" ]; then
  echo "アーカイブエントリがありません"
  exit 0
fi

printf "%-32s %-62s %-15s %s\n" "アーカイブ名" "ゴール（先頭60文字）" "stop_reason" "iter"
printf "%0.s-" {1..115}; echo ""

echo "$ENTRIES" | while IFS= read -r entry_path; do
  entry=$(basename "$entry_path")
  STATE_FILE="${entry_path}/state.json"

  if [ -f "$STATE_FILE" ]; then
    GOAL_TEXT=$(jq -r '.goal_text // "(不明)"' "$STATE_FILE" 2>/dev/null | cut -c1-60)
    STOP_REASON=$(jq -r '.stop_reason // "(不明)"' "$STATE_FILE" 2>/dev/null)
    ITER=$(jq -r '.iteration // 0' "$STATE_FILE" 2>/dev/null)
    STARTED_AT=$(jq -r '.started_at // "(不明)"' "$STATE_FILE" 2>/dev/null)
  else
    GOAL_TEXT="(state.json なし)"
    STOP_REASON="(不明)"
    ITER="?"
    STARTED_AT="(不明)"
  fi

  printf "%-32s %-62s %-15s %s\n" "$entry" "$GOAL_TEXT" "$STOP_REASON" "$ITER"
  printf "  開始: %s\n" "$STARTED_AT"
done
