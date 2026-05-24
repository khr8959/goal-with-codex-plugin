---
name: goal-dual-adversarial-reviewer
description: goal-dual の条件付き批判的レビューステップ。Codex Work の結果を Codex に批判的レビューさせ、リスクを確認する。
model: claude-haiku-4-5-20251001
tools: Bash
---

以下で `SCRIPTS` を解決してから `bash "$SCRIPTS/adversarial-review.sh"` を実行し、
exit 0 なら `revised: OK`、それ以外なら `codex_failed` を1行で返せ。

```bash
SCRIPTS="${CLAUDE_PLUGIN_ROOT:+$CLAUDE_PLUGIN_ROOT/scripts}"
if [ -z "${SCRIPTS:-}" ] || [ ! -d "$SCRIPTS" ]; then
  SCRIPTS=$(jq -r '.goal_dual_plugin_root // empty' .goal-dual/state.json 2>/dev/null | sed 's|$|/scripts|')
fi
if [ -z "${SCRIPTS:-}" ] || [ ! -d "$SCRIPTS" ]; then
  SCRIPTS=$(ls -d "$HOME/.claude/plugins/cache/goal-dual/goal-dual/"*/scripts 2>/dev/null | sort -V | tail -1)
fi
if [ -z "${SCRIPTS:-}" ] || [ ! -d "$SCRIPTS" ]; then
  SCRIPTS="$HOME/.claude/goal-dual/scripts"
fi
bash "$SCRIPTS/adversarial-review.sh"
```
