# goal-dual Release Checklist

Use this checklist before posting a public release.

## Required Checks

- [ ] `npm run verify` passes locally
- [ ] GitHub Actions `verify` passes on `main`
- [ ] `/goal-dual:doctor` reports safe defaults
- [ ] `/goal-dual:dashboard` starts and prints a local URL
- [ ] README quick start matches the current commands
- [ ] Marketplace description matches the current positioning
- [ ] No `.goal-dual/` or `.goal-dual-archive/` content is committed
- [ ] No API keys, tokens, private logs, or local screenshots are committed

## Manual Smoke Test

Run these in a small test repository:

```text
/goal-dual:doctor
/goal-dual:plan Add a tiny README note and verify with npm test if available
/goal-dual:run
/goal-dual:status
/goal-dual:dashboard
```

Confirm:

- The run does not create commits by default.
- Scope violations stop in `enforce` mode.
- The dashboard updates from `.goal-dual/progress.txt` and `.goal-dual/events.jsonl`.
- `final-report.md` gives a human-reviewable summary.

## Positioning

Primary message:

> AI acceleration without handing over responsibility.

More specific message:

> Claude supervises. Codex implements. goal-dual keeps the loop bounded, reviewable, and able to stop.

Do not claim:

- It is safe for every repository.
- It replaces human review.
- It can handle production data, auth, billing, or destructive changes without human approval.
- It is a full multi-agent platform.

The product promise is narrower:

> Bounded, acceptance-driven implementation loops for Claude Code users.
