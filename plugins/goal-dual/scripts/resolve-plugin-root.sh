#!/bin/bash
# goal-dual/scripts/resolve-plugin-root.sh — CLAUDE_PLUGIN_ROOT を解決して export
# 実装は lib.sh の resolve_plugin_root() に集約済み。本ファイルは shim。
# Usage: source "$HOME/.claude/goal-dual/scripts/resolve-plugin-root.sh"

# このスクリプトは source される前提のため exit せずに return する。
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib.sh"

if [ -z "${CLAUDE_PLUGIN_ROOT:-}" ]; then
  CLAUDE_PLUGIN_ROOT=$(resolve_plugin_root)
fi

if [ -z "${CLAUDE_PLUGIN_ROOT:-}" ]; then
  echo "codex@openai-codex プラグインが見つかりません。インストールを確認してください。" >&2
  return 1 2>/dev/null || exit 1
fi

if [ ! -f "$CLAUDE_PLUGIN_ROOT/scripts/codex-companion.mjs" ]; then
  echo "codex-companion.mjs が見つかりません: $CLAUDE_PLUGIN_ROOT/scripts/" >&2
  return 1 2>/dev/null || exit 1
fi

export CLAUDE_PLUGIN_ROOT
