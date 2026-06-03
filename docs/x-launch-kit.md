# goal-dual X Launch Kit

## Primary Post

```text
I built goal-dual because AI coding agents are powerful, but self-grading agents make me nervous.

Claude acts as PM/reviewer.
Codex acts as implementer.

goal-dual turns that into a Claude Code workflow:
plan -> implement -> test -> review -> stop when a human should decide

It now includes:
- safe defaults: no auto-commit, scope enforce, high-risk stop
- /goal-dual:doctor
- /goal-dual:status
- /goal-dual:explain-stop
- local live dashboard
- typed agent packets instead of long agent-to-agent chat

AI acceleration without handing over responsibility.
```

## Short Post

```text
AI coding agents are useful.
Letting them self-grade everything is not.

goal-dual makes Claude supervise Codex:
- Claude plans and reviews
- Codex implements
- tests provide evidence
- high-risk work stops
- progress is visible in a local dashboard

Built for Claude Code.
```

## Japanese Post

```text
AIに実装を任せたい。
でも責任まで手放したくない。

そのために goal-dual を作っています。

Claude = PM / レビュアー
Codex = 実装者

plan -> 実装 -> test -> review -> 危ない時は止まる

自動commitは既定off。
scope違反は既定で停止。
risk=highも人間確認。
進捗はローカルダッシュボードで追えます。
```

## Demo Script

1. Open a small repository.
2. Run `/goal-dual:doctor`.
3. Run `/goal-dual:dashboard`.
4. Run `/goal-dual:plan <small scoped request>`.
5. Run `/goal-dual:run`.
6. Show the dashboard updating.
7. Show `final-report.md`.
8. Show that no commit was created by default.

## What Not To Say

Avoid:

- "safe for everyone"
- "fully autonomous"
- "no review needed"
- "replaces Claude Code / Codex / Copilot"
- "enterprise ready"

Say:

- "safety-oriented"
- "human-reviewable"
- "bounded"
- "acceptance-driven"
- "local dashboard"
- "stops when a human should decide"
