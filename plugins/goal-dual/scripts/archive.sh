#!/bin/bash
# goal-dual/scripts/archive.sh — COMPLETE 時に .goal-dual/ をアーカイブへ移動
# Usage: bash archive.sh
# .goal-dual/state.json が存在する前提で呼び出すこと
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib.sh"

if [ ! -f ".goal-dual/state.json" ]; then
  echo "アーカイブ対象が見つかりません（.goal-dual/state.json が存在しない）" >&2
  exit 1
fi

# goal-slug 生成（goal_text の先頭 40 文字以内、英数字・ハイフンのみ）
GOAL_TEXT=$(jq -r '.goal_text // "unknown"' .goal-dual/state.json 2>/dev/null || echo "unknown")
SLUG=$(python3 -c "
import sys, re
t = sys.argv[1][:40].lower()
t = re.sub(r'[^a-z0-9]+', '-', t)
t = re.sub(r'-+', '-', t).strip('-')
print(t or 'goal')
" "$GOAL_TEXT")
[ -z "$SLUG" ] && SLUG="goal"

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
ARCHIVE_DIR=".goal-dual-archive/${TIMESTAMP}-${SLUG}"

# .goal-dual-archive/ を .gitignore に追記（重複チェック付き）
GITIGNORE=".gitignore"
if ! grep -qxF '.goal-dual-archive/' "$GITIGNORE" 2>/dev/null; then
  printf '\n.goal-dual-archive/\n' >> "$GITIGNORE"
  echo ".gitignore に .goal-dual-archive/ を追記しました"
fi

# アーカイブ先ディレクトリを作成して mv（mv が失敗したら set -e で即停止）
mkdir -p "$(dirname "$ARCHIVE_DIR")"
mv .goal-dual/ "$ARCHIVE_DIR/"
echo "アーカイブ完了: $ARCHIVE_DIR"
