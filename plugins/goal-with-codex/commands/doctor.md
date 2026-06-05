---
description: goal-with-codex の依存関係、公式 Codex plugin、作業ツリー状態を診断する
disable-model-invocation: true
allowed-tools: Bash
---

Run the doctor command:

```bash
PLUGIN_ROOT=$(ls -d "$HOME/.claude/plugins/cache/goal-with-codex/goal-with-codex/"*/ 2>/dev/null | sort -V | tail -1 | sed 's|/$||')
if [ -z "$PLUGIN_ROOT" ] && [ -d "$HOME/.claude/skills/goal-with-codex" ]; then
  PLUGIN_ROOT="$HOME/.claude/skills/goal-with-codex"
fi
if [ -z "$PLUGIN_ROOT" ] || [ ! -x "$PLUGIN_ROOT/bin/goal-with-codex" ]; then
  echo "goal-with-codex plugin root not found" >&2
  exit 1
fi
"$PLUGIN_ROOT/bin/goal-with-codex" doctor
```
