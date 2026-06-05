# goal-with-codex Agent Protocol

Claude and Codex do not chat like humans in this plugin.

The protocol is intentionally small:

| Artifact | Path | Meaning |
| --- | --- | --- |
| Goal contract | `.goal-with-codex/request/goal.md` | Claude's technical rewrite of the user's request |
| Codex prompt | `.goal-with-codex/state/codex-prompt-<n>.md` | The bounded request passed to official Codex `task` |
| Codex task JSON | `.goal-with-codex/state/codex-task-<n>.json` | Official Codex plugin task result |
| Eval excerpt | `.goal-with-codex/state/eval-output.log` | Redacted tail of the detected test command |
| Evidence | `.goal-with-codex/state/evidence-latest.json` | The compact packet Claude reads for the next decision |
| Events | `.goal-with-codex/events.jsonl` | Timeline for status and dashboard |

## Routing

| Situation | Codex action |
| --- | --- |
| First iteration | `task --write --json --prompt-file ...` |
| Continue same goal | `task --write --json --prompt-file ... --resume-last` |
| Eval passed or skipped | `review --wait --json --scope working-tree` |
| High-risk goal | Also run `adversarial-review --wait --json --scope working-tree` |

High risk is triggered by words such as auth, payment, database, migration, token, secret, or production, or by broad file churn.
