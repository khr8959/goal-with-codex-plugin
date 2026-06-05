#!/bin/bash
# goal-with-codex plugin local installer
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_SRC="$REPO_DIR/plugins/goal-with-codex"
CLAUDE_DIR="$HOME/.claude"
TARGET="$CLAUDE_DIR/skills/goal-with-codex"

echo "=== goal-with-codex plugin local install ==="
echo ""

for cmd in jq node; do
  command -v "$cmd" >/dev/null || { echo "missing required command: $cmd" >&2; exit 1; }
done

if ! ls "$CLAUDE_DIR/plugins/cache/openai-codex/codex/"*"/scripts/codex-companion.mjs" >/dev/null 2>&1; then
  echo "WARN codex@openai-codex plugin was not found. Install the official Codex plugin in Claude Code first."
fi

mkdir -p "$TARGET"

echo "Installing plugin to: $TARGET"
cp -R "$PLUGIN_SRC/.claude-plugin" "$TARGET/"
cp -R "$PLUGIN_SRC/commands" "$TARGET/"
cp -R "$PLUGIN_SRC/scripts" "$TARGET/"
cp -R "$PLUGIN_SRC/bin" "$TARGET/"
chmod +x "$TARGET/bin/goal-with-codex"

echo ""
echo "Installed. In Claude Code, run:"
echo "  /reload-plugins"
echo "  /goal-with-codex:doctor"
echo "  /goal-with-codex:run <goal>"
echo ""
echo "If you previously used goal-dual, remove stale standalone commands manually from:"
echo "  $CLAUDE_DIR/commands/goal-dual*.md"
