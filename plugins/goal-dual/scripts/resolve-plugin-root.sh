#!/bin/bash
# goal-dual/scripts/resolve-plugin-root.sh — CLAUDE_PLUGIN_ROOT を解決して export
# Usage: source "$HOME/.claude/goal-dual/scripts/resolve-plugin-root.sh"

if [ -z "${CLAUDE_PLUGIN_ROOT:-}" ]; then
  CLAUDE_PLUGIN_ROOT=$(
    ls -d "$HOME/.claude/plugins/cache/openai-codex/codex/"*/ 2>/dev/null \
      | sort -V | tail -1 | sed 's|/$||'
  )
fi

if [ -z "$CLAUDE_PLUGIN_ROOT" ]; then
  echo "codex@openai-codex プラグインが見つかりません。インストールを確認してください。" >&2
  exit 1
fi

if [ ! -f "$CLAUDE_PLUGIN_ROOT/scripts/codex-companion.mjs" ]; then
  echo "codex-companion.mjs が見つかりません: $CLAUDE_PLUGIN_ROOT/scripts/" >&2
  exit 1
fi

export CLAUDE_PLUGIN_ROOT
