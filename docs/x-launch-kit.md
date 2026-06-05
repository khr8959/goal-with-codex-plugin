# X Launch Kit

## Short

I rebuilt the plugin as **goal-with-codex**.

Claude keeps the goal. Official Codex plugin does the implementation iteration. Claude reads one compact evidence packet and decides whether to continue.

`/goal-with-codex:run <goal>`

## Longer

Claude Code `/goal` is great, but Claude does not need to spend every iteration doing codebase implementation work.

goal-with-codex turns the user's request into a goal contract, calls the official Codex plugin for one implementation step, runs tests when it can detect them, asks Codex for review, then writes:

`.goal-with-codex/state/evidence-latest.json`

It is not an agent chat bridge. It is a small control layer for people who want agents to move, while keeping final responsibility visible.

## Demo

1. Run `/goal-with-codex:doctor`.
2. Run `/goal-with-codex:run Fix the failing validation test without changing the public API.`
3. Open `/goal-with-codex:status`.
4. Show `.goal-with-codex/state/evidence-latest.json`.
