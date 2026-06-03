---
description: goal-dual の進捗をブラウザで追えるローカルダッシュボードを起動する
argument-hint: '[port]'
disable-model-invocation: true
allowed-tools: Bash
---

## goal-dual dashboard

ローカルホストで進捗ダッシュボードを起動します。引数にポート番号を指定できます。
既に起動している場合は既存URLを表示します。指定ポートが使用中の場合は、次の空きポートへ自動で移動します。

```bash
SCRIPTS="${CLAUDE_PLUGIN_ROOT:+$CLAUDE_PLUGIN_ROOT/scripts}"
if [ -z "${SCRIPTS:-}" ] || [ ! -d "$SCRIPTS" ]; then
  SCRIPTS=$(jq -r ' .goal_dual_plugin_root // empty ' .goal-dual/state.json 2>/dev/null | sed 's|$|/scripts|')
fi
if [ -z "${SCRIPTS:-}" ] || [ ! -d "$SCRIPTS" ]; then
  SCRIPTS=$(ls -d "$HOME/.claude/plugins/cache/goal-dual/goal-dual/"*/scripts 2>/dev/null | sort -V | tail -1)
fi
if [ -z "${SCRIPTS:-}" ] || [ ! -d "$SCRIPTS" ]; then
  SCRIPTS="$HOME/.claude/goal-dual/scripts"
fi
PORT="${ARGUMENTS:-3762}"
bash "$SCRIPTS/dashboard.sh" "$PORT"
```
