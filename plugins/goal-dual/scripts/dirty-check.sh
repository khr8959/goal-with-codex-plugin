#!/bin/bash
# goal-dual/scripts/dirty-check.sh — .goal-dual/ を除外した dirty check
# 実装は lib.sh の goal_dual_dirty_check() に集約済み。本ファイルは shim。
# 終了コード: 0=クリーン / 1=dirty（stdout に変更ファイル一覧）
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

# no-git モードではスキップ
NO_GIT=$(jq -r '.no_git // false' .goal-dual/state.json 2>/dev/null || echo "false")
[ "$NO_GIT" = "true" ] && exit 0

DIRTY=$(goal_dual_dirty_check)
if [ -n "$DIRTY" ]; then
  echo "$DIRTY"
  exit 1
fi
exit 0
