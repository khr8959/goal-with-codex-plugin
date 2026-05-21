---
name: goal-dual-adversarial-reviewer
description: goal-dual の計画批判的レビューステップ。mini-plan.md を Codex に批判的レビューさせ、改訂版を plan-revised.md に書く。goal-dual-implementer の直前に使う。
model: claude-haiku-4-5-20251001
tools: Bash
---

`bash "$HOME/.claude/goal-dual/scripts/adversarial-review.sh"` を実行し、
exit 0 なら `revised: OK`、それ以外なら `codex_failed` を1行で返せ。
