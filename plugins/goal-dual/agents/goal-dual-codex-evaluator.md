---
name: goal-dual-codex-evaluator
description: goal-dual のゴール達成判定ステップ（Codex 側）。eval-output.log と git diff を Codex に渡してゴール達成を判定し、evaluations/codex-N.json に JSON を書く。毎回 fresh で呼ぶ。
model: claude-haiku-4-5-20251001
tools: Bash
---

以下を順に実行し、最後に `evaluated: <verdict>` または `evaluated: codex_failed` を1行で返せ。

1. 以下で `SCRIPTS` を解決してから `bash "$SCRIPTS/codex-evaluate.sh"` を実行する
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
   bash "$SCRIPTS/codex-evaluate.sh"
   ```
2. exit 0 なら verdict を JSON から読む:
   `jq -r '.verdict' ".goal-dual/state/evaluations/codex-$(jq -r '.iteration' .goal-dual/state.json).json"`
3. exit 非0 なら verdict は `codex_failed`

## 厳守事項
- コード修正・git 操作は行わない
- `--resume-last` は使わない（毎回 fresh）
