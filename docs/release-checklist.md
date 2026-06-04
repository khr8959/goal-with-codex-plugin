# goal-dual Release Checklist

Use this before announcing goal-dual publicly.

## Product Fit

- [ ] README says this is only for Claude Code `/goal` delegation.
- [ ] Dynamic workflow support is not promised.
- [ ] Exposed commands are limited to `run`, `status`, `dashboard`, and `doctor`.
- [ ] The primary output is `.goal-dual/state/evidence-latest.json`.
- [ ] No automatic commit, branch creation, push, or PR flow is advertised.

## Local Verification

```bash
npm run verify
```

Manual smoke test in a disposable repository:

```text
/goal-dual:doctor
/goal-dual:run Make a tiny README wording change.
/goal-dual:status
```

Check:

- [ ] `.goal-dual/state/evidence-latest.json` exists.
- [ ] `status` is one of `awaiting_claude_review`, `needs_fix`, or `stopped`.
- [ ] `changed_files` does not include `.goal-dual/`.
- [ ] A second `/goal-dual:run` continues the same goal without stopping only because the previous Codex step left files dirty.
- [ ] High-risk or forbidden-scope output stops.

## Launch Claim

Safe claim:

> goal-dual lets Claude Code `/goal` delegate implementation steps to Codex, then gives Claude a compact evidence packet for the next decision.

Avoid claiming:

- Fully autonomous workflow engine
- Dynamic workflow integration
- No human review needed
- Automatic PR/push automation
