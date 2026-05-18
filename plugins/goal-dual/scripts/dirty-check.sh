#!/bin/bash
# goal-dual/scripts/dirty-check.sh — .goal-dual/ を除外した dirty check
# 終了コード: 0=クリーン / 1=dirty（stdout に変更ファイル一覧）
set -euo pipefail

# no-git モードではスキップ
NO_GIT=$(jq -r '.no_git // false' .goal-dual/state.json 2>/dev/null)
if [ "$NO_GIT" = "true" ]; then
  exit 0
fi

DIRTY=$(git status --porcelain | grep -v -E \
  '^\?\? \.goal-dual/$|^\?\? \.goal-dual/.*|^.. \.goal-dual/.*' \
  || true)

if [ -n "$DIRTY" ]; then
  echo "$DIRTY"
  exit 1
fi

exit 0
