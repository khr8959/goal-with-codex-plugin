# goal-dual Agent Protocol

goal-dual does not make Claude and Codex talk like humans.

The core rule is:

> Agents exchange typed packets. Claude reads compact evidence.

## Roles

| Role | Responsibility |
|---|---|
| Claude `/goal` | Owns the goal loop, final judgment, and user-facing responsibility |
| goal-dual driver | Creates state, delegates one Codex step, runs eval, writes evidence |
| Codex | Investigates code, edits files, returns a short work result |
| shell | Runs a detected eval command and stores redacted output |

## Packet Types

| Type | Path | Purpose |
|---|---|---|
| `WORK_REQUEST` | `.goal-dual/state/work-request-<n>.json` | A bounded implementation request for Codex |
| `WORK_RESULT` | `.goal-dual/codex-work-result.json` | Codex's changed files, summary, risk, and next action |
| `EVAL_OUTPUT` | `.goal-dual/state/eval-output.log` | Redacted eval log excerpt |
| `EVIDENCE_PACKET` | `.goal-dual/state/evidence-latest.json` | The only packet Claude needs to read for the next `/goal` decision |
| `EVENT` | `.goal-dual/events.jsonl` | Machine-readable timeline for status and dashboard |

## Evidence Status

| Status | Meaning | Expected Claude action |
|---|---|---|
| `awaiting_claude_review` | Codex finished and eval did not fail | Review evidence/diff, then mark complete or run another step |
| `needs_fix` | Eval command failed | Run `/goal-dual:run` again with no arguments if the fix is still within scope |
| `stopped` | Safety or human-judgment stop | Ask the user or inspect the stop reason |

## Design Constraints

- One `/goal-dual:run` call delegates one Codex step.
- Claude should not replay Codex logs into its conversation unless a human asks for debugging detail.
- Full logs stay in `.goal-dual/logs/`; Claude reads `.goal-dual/state/evidence-latest.json`.
- The first step stops on pre-existing dirty state. Later steps can continue with Codex's own uncommitted changes.
- High-risk and forbidden-scope changes stop by default.

This keeps goal-dual focused on Claude `/goal` delegation instead of becoming a general dynamic workflow engine.
