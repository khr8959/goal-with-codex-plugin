#!/bin/bash
# goal-dual/scripts/resolve-codex-plugin-root.sh — CODEX_PLUGIN_ROOT を解決して export
# Usage: source "$HOME/.claude/goal-dual/scripts/resolve-codex-plugin-root.sh"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib.sh"

if [ -z "${CODEX_PLUGIN_ROOT:-}" ]; then
  CODEX_PLUGIN_ROOT=$(resolve_codex_plugin_root)
fi

if [ -z "${CODEX_PLUGIN_ROOT:-}" ]; then
  echo "codex@openai-codex プラグインが見つかりません。インストールを確認してください。" >&2
  return 1 2>/dev/null || exit 1
fi

if [ ! -f "$CODEX_PLUGIN_ROOT/scripts/codex-companion.mjs" ]; then
  echo "codex-companion.mjs が見つかりません: $CODEX_PLUGIN_ROOT/scripts/" >&2
  return 1 2>/dev/null || exit 1
fi

export CODEX_PLUGIN_ROOT
