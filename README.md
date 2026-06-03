<p align="center">
  <img src="assets/demo.svg" alt="goal-dual workflow animation" width="100%">
</p>

# goal-dual

<p align="center">
  <strong>A Claude Code plugin for people who want AI acceleration without handing over responsibility.</strong>
</p>

<p align="center">
  <a href="#installation">Install</a> ·
  <a href="#quick-start">Quick Start</a> ·
  <a href="#workflow">Workflow</a> ·
  <a href="#commands">Commands</a> ·
  <a href="#safety">Safety</a> ·
  <a href="README.ja.md">日本語</a>
</p>

**goal-dual** is a Claude Code plugin that integrates the OpenAI Codex plugin into a safety-oriented iterative development loop.

Claude handles goal clarification, orchestration, and final judgment. Codex handles code investigation, implementation, and initial evaluation. The loop runs in small iterations, checks evidence, and stops when a human should decide.

## Why goal-dual?

| Pain point | What goal-dual does |
|---|---|
| Hard to write a precise goal | `/goal-dual:plan` turns a vague request into an actionable plan |
| One shot rarely gets it right | Codex work + evaluation runs as repeated iterations |
| Claude alone is heavy on context | Code investigation, implementation, and first-pass evaluation are delegated to Codex |
| Want to fix based on test output | Runs `npm test` / `pytest` etc. and decides next action from results |
| Want to keep a work log | Generates a PR description and execution history on completion |
| Don't trust AI self-grading | Codex implements, then Claude performs final checks and review |

## Best For

- Fixing failing tests in an existing codebase
- Small to medium feature additions with clear scope
- Scoped refactors
- Pre-PR review
- Claude + Codex users who want less manual handoff

## Not For

- Large product decisions with unclear requirements
- Fully automated changes to production data, billing, auth, or destructive flows
- Large parallel agent swarms
- Push/PR automation without human review

## Installation

Recommended: install via the Claude Code Marketplace.

```text
/install codex@openai-codex
/plugin marketplace add khr8959/goal-dual-plugin
/plugin install goal-dual@goal-dual
/reload-plugins
```

With Marketplace install, you do **not** need to clone `goal-dual-plugin/` into your project. Claude Code places the plugin in its local cache automatically.

After installing, start with:

```text
/goal-dual:doctor
```

## Quick Start

When you have a clear goal:

```text
/goal-dual:run Add user authentication. Issue a JWT access token and protect the /api/me endpoint.
```

When you're not sure how to phrase the goal:

```text
/goal-dual:plan I want to show user info after login
/goal-dual:run
```

`/goal-dual:plan` does **not** start implementation — it writes a plan, completion criteria, scope, and open questions to `.goal-dual/plan/`. Once the plan is `ready`, run `/goal-dual:run` with no arguments to start implementing from that plan.

## Workflow

`/goal-dual:run` repeats the following loop:

1. Claude clarifies the goal, completion criteria, and scope of changes
2. goal-dual delegates work to the OpenAI Codex plugin
3. Codex investigates the codebase and implements the required changes
4. The shell runs the test command
5. Codex performs an initial evaluation; Claude decides whether to continue, complete, or stop

If the completion criteria are not met, the next iteration begins. If the goal and existing tests conflict, or a judgment call is too difficult, the loop stops and waits for human input.

## Commands

| Command | Purpose |
|---|---|
| `/goal-dual:run <goal>` | Iterate until the goal is achieved |
| `/goal-dual:run` | Start implementing from a ready plan |
| `/goal-dual:plan <request>` | Turn a vague request into an implementation plan |
| `/goal-dual:doctor` | Check dependencies, working tree state, and safety defaults |
| `/goal-dual:status` | Show the current run status, stop reason, and next review point |
| `/goal-dual:explain-stop` | Explain why goal-dual stopped and how to recover |
| `/goal-dual:review` | Review the current changes |
| `/goal-dual:history` | Show past goal-dual execution history |
| `/goal-dual:route <request>` | Decide whether goal-dual is the right tool |

## Responsibilities

| Role | Handled by |
|---|---|
| Goal clarification, orchestration, final judgment | Claude |
| Code investigation, implementation, initial evaluation | OpenAI Codex plugin |
| Test execution | shell |

## Generated Files

goal-dual creates the following working directories in your project:

| Path | Contents |
|---|---|
| `.goal-dual/` | Current run state, logs, evaluation results |
| `.goal-dual/plan/` | Plans created by `/goal-dual:plan` |
| `.goal-dual-archive/` | Execution history archived after completion |

These are working files. Do not commit them to Git.

## Requirements

- Claude Code
- Node.js 18+
- `jq`
- `git`
- [Codex CLI](https://github.com/openai/codex)
- The `codex@openai-codex` Claude Code plugin

## Safety

- goal-dual modifies code, but does not create commits by default.
- If the working tree is dirty before a run, goal-dual stops immediately.
- Forbidden scope changes stop by default.
- `risk=high` Codex work stops by default.
- Test logs are redacted before being sent to LLM evaluation steps.
- Test commands are restricted to common commands, but commands such as `npm test` and `make test` execute project-defined scripts. Use them only in repositories you trust.
- Do not commit `.goal-dual/` or `.goal-dual-archive/` to public repositories — they contain execution logs.
- Do not include API keys, tokens, or secrets in issues, README files, plans, or goals.

## Environment Variables

| Variable | Description | Default |
|---|---|---|
| `GOAL_DUAL_REVIEW_LEVEL` | Code review strictness: `strict` / `standard` / `relaxed` | `standard` |
| `GOAL_DUAL_STAGNATION_THRESHOLD` | How many identical verdicts in a row before stopping | `3` |
| `GOAL_DUAL_SCOPE_MODE` | Whether forbidden paths hard-stop: `enforce` / `advisory` | `enforce` |
| `GOAL_DUAL_WIP_COMMITS` | Whether to create WIP commits for incomplete iterations: `1` / `0` | `0` |
| `GOAL_DUAL_FINAL_COMMIT` | Whether to create the final completion commit: `1` / `0` | `0` |
| `GOAL_DUAL_ALLOW_HIGH_RISK` | Whether `risk=high` work may continue automatically: `1` / `0` | `0` |

## Agent Protocol

goal-dual does not make Claude and Codex chat like humans. Claude creates a work contract; Codex returns a short JSON work result.

See `docs/agent-protocol.md`.

## Manual Installation

Manual installation is only recommended when developing or testing the plugin itself.

```bash
cd ~/Documents/GitHub
git clone https://github.com/khr8959/goal-dual-plugin.git
cd goal-dual-plugin
bash install.sh
```

Run `git clone` from **outside** the `goal-dual-plugin` directory. Cloning again from inside will create a nested `goal-dual-plugin/goal-dual-plugin/` copy.

## Uninstall

If installed via Marketplace:

```text
/plugin uninstall goal-dual
```

If installed manually:

```bash
rm ~/.claude/commands/goal-dual.md
rm ~/.claude/commands/goal-dual-plan.md
rm ~/.claude/commands/goal-dual-history.md
rm ~/.claude/commands/goal-dual-review.md
rm ~/.claude/commands/goal-dual-route.md
rm ~/.claude/agents/goal-dual-*.md
rm -rf ~/.claude/goal-dual/
```

## File Structure

```text
goal-dual-plugin/
├── .claude-plugin/
│   └── marketplace.json
├── assets/
│   └── goal-dual-flow.svg
├── docs/
│   └── agent-protocol.md
├── schemas/
│   ├── state.schema.json
│   └── work-result.schema.json
├── plugins/
│   └── goal-dual/
│       ├── .claude-plugin/
│       │   └── plugin.json
│       ├── agents/
│       ├── commands/
│       └── scripts/
├── install.sh
├── package.json
└── README.md
```

## License

MIT
