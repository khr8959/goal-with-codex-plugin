# goal-with-codex

`goal-with-codex` is a Claude Code plugin skill that brings the official `codex@openai-codex` plugin into a goal-shaped workflow.

It does not reimplement Codex, and it does not patch Claude Code's private `/goal` internals. Claude turns a vague request into a precise goal contract. The plugin driver routes one implementation iteration through the official Codex plugin, runs the project's test command when it can detect one, asks Codex for a review, then writes a compact evidence packet for Claude to judge.

## Why this exists

Claude Code's goal-driven workflow is useful, but letting Claude spend every iteration reading the codebase, editing files, reading logs, and reviewing the result can burn a lot of context. Codex is already good at codebase-local implementation and review. This plugin uses that official Codex surface as a worker inside a smaller loop:

1. Claude clarifies the user's goal into `.goal-with-codex/request/goal.md`.
2. `goal-with-codex` calls `codex-companion.mjs task --write --json`.
3. The driver runs a detected test command such as `npm test`, `pytest`, or `go test ./...`.
4. If the eval passes or no eval exists, the driver calls Codex `review`.
5. Claude reads `.goal-with-codex/state/evidence-latest.json` and decides whether to finish or continue.

Claude stays responsible. Codex does the implementation iteration.

## Target users

This is for people who want AI agents to keep moving, but do not want to hand off judgment completely:

- solo builders using Claude Code for long coding sessions
- plugin and tooling authors who want smaller Claude context usage
- engineers who like `/goal`, but want implementation work delegated to Codex
- teams that want a visible stop point before accepting or committing AI changes

It is not a general multi-agent framework, dynamic workflow engine, or agent chat bridge.

## Install

First install the official Codex plugin in Claude Code. Then install this plugin:

```text
/plugin marketplace add khr8959/goal-with-codex-plugin
/plugin install goal-with-codex@goal-with-codex
```

For local development:

```bash
npm run install-local
```

## Commands

| Command | Purpose |
| --- | --- |
| `/goal-with-codex:doctor` | Check local prerequisites and the official Codex plugin |
| `/goal-with-codex:run <goal>` | Start a goal contract and run one Codex implementation iteration |
| `/goal-with-codex:run` | Continue the same goal, resuming the prior Codex thread |
| `/goal-with-codex:status` | Show current state and latest evidence |
| `/goal-with-codex:dashboard` | Start a local dashboard for progress |

## Evidence

The main output is:

```text
.goal-with-codex/state/evidence-latest.json
```

It contains the status, recommendation, Codex task reference, review reference, eval result, changed files, and next commands. Claude should read this compact packet instead of re-reading the full implementation conversation.

## Development

```bash
npm run verify
```

The test suite uses a stub of the official Codex plugin boundary. It verifies the routing logic, resume behavior, evidence output, and shell-safe goal-file handling.
