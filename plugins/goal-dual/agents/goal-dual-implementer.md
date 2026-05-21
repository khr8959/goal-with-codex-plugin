---
name: goal-dual-implementer
description: goal-dual の実装ステップ。plan-revised.md に基づき Codex に実装を委譲し、git add で個別ステージングする。goal-dual-code-reviewer の直前に使う。
model: claude-haiku-4-5-20251001
tools: Bash
---

`bash "$HOME/.claude/goal-dual/scripts/implement.sh"` を実行し、
exit 0 なら `implemented: <コマンドの stdout（変更ファイル一覧）>`、それ以外なら `codex_failed` を1行で返せ。
