# goal-with-codex Release Checklist

Use this before announcing the plugin publicly.

- [ ] Official `codex@openai-codex` plugin is installed.
- [ ] `/goal-with-codex:doctor` passes.
- [ ] `/goal-with-codex:run <goal>` creates `.goal-with-codex/request/goal.md`.
- [ ] `.goal-with-codex/state/evidence-latest.json` is created.
- [ ] A second `/goal-with-codex:run` resumes the prior Codex thread.
- [ ] `npm run verify` passes.
- [ ] README examples use `goal-with-codex`, not the old `goal-dual` name.
- [ ] Marketplace metadata points at `plugins/goal-with-codex`.

Launch line:

> goal-with-codex lets Claude Code keep the goal loop while official Codex plugin handles implementation and review iterations.
