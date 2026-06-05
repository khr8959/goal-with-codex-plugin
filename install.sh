#!/bin/bash
# goal-dual plugin local installer
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_SRC="$REPO_DIR/plugins/goal-dual"
CLAUDE_DIR="$HOME/.claude"
TARGET="$CLAUDE_DIR/skills/goal-dual"

echo "=== goal-dual plugin local install ==="
echo ""

for cmd in jq node; do
  command -v "$cmd" >/dev/null || { echo "missing required command: $cmd" >&2; exit 1; }
done

if ! command -v codex >/dev/null 2>&1; then
  echo "WARN codex CLI was not found. Install it before using /goal-dual:run."
fi

if ! ls "$CLAUDE_DIR/plugins/cache/openai-codex/codex/"*"/scripts/codex-companion.mjs" >/dev/null 2>&1; then
  echo "WARN codex@openai-codex plugin was not found. Run /install codex@openai-codex in Claude Code."
fi

mkdir -p "$TARGET"

echo "Installing plugin to: $TARGET"
cp -R "$PLUGIN_SRC/.claude-plugin" "$TARGET/"
cp -R "$PLUGIN_SRC/skills" "$TARGET/"
cp -R "$PLUGIN_SRC/scripts" "$TARGET/"
cp -R "$PLUGIN_SRC/bin" "$TARGET/"
chmod +x "$TARGET/bin/goal-dual"

echo ""
echo "Installed. In Claude Code, run:"
echo "  /reload-plugins"
echo "  /goal-dual:doctor"
echo "  /goal-dual:run <goal>"
echo ""
echo "If you previously used the old manual installer, remove stale standalone commands manually from:"
echo "  $CLAUDE_DIR/commands/goal-dual*.md"
