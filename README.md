# goal-dual

**Use Codex for the implementation step around Claude Code `/goal`.**

goal-dual is a small Claude Code plugin for people who like Claude's goal-driven loop, but do not want Claude to spend a large context window reading, editing, testing, and re-reading the codebase every iteration.

Claude stays responsible for the goal loop and final judgment. Codex does the code investigation and implementation step. goal-dual returns a compact evidence packet for Claude to review.

Strictly speaking, goal-dual does not patch Claude Code's built-in `/goal` internals. Claude Code does not expose that internal implementation as a public plugin API. Instead, goal-dual provides a namespaced plugin skill, `/goal-dual:run`, that you can invoke from a Claude `/goal` loop whenever the next step should be implementation work.

## What It Is

goal-dual is not a general multi-agent workflow engine.

It does one thing:

```text
Claude /goal decides what should happen next
        ↓
goal-dual delegates one implementation step to Codex
        ↓
tests run locally when a known eval command is detected
        ↓
Claude reads .goal-dual/state/evidence-latest.json
```

This keeps Claude's visible context small while still leaving responsibility with Claude and the user.

goal-dual uses Claude Code's current plugin skill layout (`skills/<name>/SKILL.md`) plus a tiny plugin `bin/goal-dual` wrapper. The skill never injects raw goal text into a shell command; new goals are written to `.goal-dual/request/goal.txt` first and passed to the driver with `--goal-file`.

## Best For

- You already use Claude Code `/goal`
- You want Codex to handle code search and implementation
- You want Claude to read a short result, not a long implementation transcript
- You want the tool to stop on dirty start state, forbidden scope changes, high-risk Codex output, or blocked decisions

## Not For

- Dynamic workflows
- Long-running multi-agent conversations
- Fully autonomous push/PR automation
- Replacing human review for risky production changes

Dynamic workflow + Codex should be a separate plugin. This repository intentionally stays focused on `/goal` delegation.

## Install

```text
/install codex@openai-codex
/plugin marketplace add khr8959/goal-dual-plugin
/plugin install goal-dual@goal-dual
/reload-plugins
```

Then check the setup:

```text
/goal-dual:doctor
```

## Quick Start

Inside Claude Code, start a goal with:

```text
/goal-dual:run Fix the failing login validation test without changing the public API.
```

After each run, goal-dual writes:

```text
.goal-dual/state/evidence-latest.json
```

Claude should use that evidence to decide one of three things:

- run `/goal-dual:run` again with no arguments
- mark the goal complete
- stop and ask the user

## Commands

| Command | Purpose |
|---|---|
| `/goal-dual:run <goal>` | Start a goal and delegate one Codex implementation step |
| `/goal-dual:run` | Continue the same goal with one more Codex step |
| `/goal-dual:status` | Show the latest evidence and next action |
| `/goal-dual:dashboard [port]` | Start a local progress dashboard |
| `/goal-dual:doctor` | Check whether Codex delegation is available |

## Evidence Packet

The important output is intentionally small:

```json
{
  "schema": "goal-dual.evidence.v1",
  "status": "awaiting_claude_review",
  "iteration": 1,
  "codex": {
    "status": "implemented",
    "summary": "...",
    "risk": "low",
    "next_action": "..."
  },
  "eval": {
    "exit_code": 0,
    "label": "passed",
    "output_ref": ".goal-dual/state/eval-output.log"
  },
  "changed_files": ["..."],
  "next_action": "Claude reviews the evidence and decides the next /goal step."
}
```

Claude and Codex do not chat like humans. goal-dual uses typed requests, typed results, and a short evidence file.

## Safety Defaults

- No commits are created by default
- The plugin does not auto-create branches
- Goal text is passed through a file, not interpolated into shell
- The first step stops if the working tree is already dirty
- Later steps may continue with Codex's previous uncommitted changes
- Forbidden scope changes stop by default
- `risk=high` Codex output stops by default
- Test logs are redacted before they are reused as AI context

## Requirements

- Claude Code
- Node.js 18+
- `jq`
- `git`
- OpenAI Codex CLI
- Claude Code `codex@openai-codex` plugin

## Development

```bash
npm test
npm run verify
```

## License

MIT
