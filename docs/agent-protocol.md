# goal-dual Agent Protocol

goal-dual does not try to make Claude and Codex chat like humans.

The core rule is:

> Agents do not chat. They exchange typed work packets.

Claude acts as the supervisor. Codex acts as the implementer. The shell provides
deterministic evidence such as test output and git state. The workflow should
move through small structured messages instead of long conversational handoffs.

## Message Types

| Type | Producer | Consumer | Purpose |
|---|---|---|---|
| `PLAN_CONTRACT` | Claude | Codex / human | Goal, acceptance criteria, scope, open questions |
| `WORK_REQUEST` | Claude / driver | Codex | One bounded implementation iteration |
| `WORK_RESULT` | Codex | driver / Claude | Changed files, summary, risk, blocker, next action |
| `EVAL_RESULT` | shell / Codex evaluator | driver / Claude | Test result and completion verdict |
| `REVIEW_RESULT` | Claude reviewer | driver / human | Final quality gate |
| `STOP_NOTICE` | driver | human | Why the run stopped and what to do next |
| `FINAL_REPORT` | driver / Claude | human | Reviewable evidence package |

## Principles

- Keep agent-to-agent messages short and typed.
- Store full human-readable logs separately.
- Pass file references and summaries instead of replaying the whole conversation.
- Treat `events.jsonl` and `state.json` as the workflow memory.
- Validate LLM output with schemas before using it for state transitions.
- Stopping is a successful safety behavior, not a crash.

## Current Artifacts

`codex-work.sh` writes a `work-request-<iteration>.json` packet before asking
Codex to implement. Codex is expected to return a `goal-dual.work-result.v1`
JSON object. The driver records important transitions in `.goal-dual/events.jsonl`.

This is intentionally small. The next step is to formalize these schemas and
move state transitions behind a reducer so the shell scripts become thin
wrappers.
