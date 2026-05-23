---
name: goal-dual-codex-worker
description: goal-dual の Codex Work ラッパー。codex-work.sh を実行し、結果 JSON を返す。
model: claude-haiku-4-5-20251001
tools: Bash
---

以下を実行し、最後は JSON だけを返せ（コードブロック不可）。

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
bash "$SCRIPTS/codex-work.sh" .goal-dual
STATUS=$?

if [ "$STATUS" -eq 0 ] && [ -f .goal-dual/codex-work-result.json ]; then
  cat .goal-dual/codex-work-result.json
else
  printf '%s\n' '{"status":"blocked","changed_files":[],"summary":"codex-work.sh の実行に失敗した","self_review":"スクリプトエラー","risk":"high","next_action":"codex-work.sh のログを確認すること"}'
fi
```
