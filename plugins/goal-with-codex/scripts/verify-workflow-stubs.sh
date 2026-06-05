#!/bin/bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
PLUGIN_BIN="$REPO_ROOT/plugins/goal-with-codex/bin/goal-with-codex"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

STUB_ROOT="$TMP_DIR/codex-plugin"
mkdir -p "$STUB_ROOT/scripts"
cat > "$STUB_ROOT/scripts/codex-companion.mjs" <<'EOF'
#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";

const [, , command, ...args] = process.argv;
if (process.env.CODEX_STUB_ARGS_LOG) {
  fs.appendFileSync(process.env.CODEX_STUB_ARGS_LOG, JSON.stringify([command, ...args]) + "\n");
}

function json(value) {
  process.stdout.write(JSON.stringify(value, null, 2) + "\n");
}

if (command === "task") {
  const cwd = process.cwd();
  const touchedFiles = [];
  if (process.env.CODEX_STUB_NO_WRITE !== "1") {
    fs.writeFileSync(path.join(cwd, "feature.txt"), "implemented by codex stub\n");
    touchedFiles.push("feature.txt");
  }
  json({
    status: "completed",
    threadId: "thread-stub",
    rawOutput: "Summary\nImplemented stub feature.\n\nChanged files\nfeature.txt\n\nVerification\nstub\n\nRemaining work\nnone\n\nRisk\nlow",
    touchedFiles,
    reasoningSummary: []
  });
} else if (command === "review") {
  json({ status: "completed", summary: "No blocking findings.", findings: [] });
} else if (command === "adversarial-review") {
  json({ status: "completed", summary: "No adversarial blocking findings.", findings: [] });
} else if (command === "setup") {
  json({ ready: true });
} else {
  console.error(`unexpected command: ${command}`);
  process.exit(2);
}
EOF
chmod +x "$STUB_ROOT/scripts/codex-companion.mjs"

WORK="$TMP_DIR/work"
mkdir -p "$WORK"
cd "$WORK"
git init -q
git config user.email test@example.com
git config user.name "Test User"
printf '# fixture\n' > README.md
git add README.md
git commit -qm "initial"

mkdir -p .goal-with-codex/request
cat > .goal-with-codex/request/goal.md <<'EOF'
# User Goal
Please add a tiny feature. $(do-not-run)

# Technical Goal
Create a fixture file through Codex stub without executing shell-looking user text.

# Acceptance Criteria
- feature.txt exists.
- Evidence is written.

# Constraints
- Keep the change scoped.

# Non-goals
- Do not commit.
EOF

export CODEX_PLUGIN_ROOT="$STUB_ROOT"
export CODEX_STUB_ARGS_LOG="$TMP_DIR/args.jsonl"

"$PLUGIN_BIN" run --goal-file .goal-with-codex/request/goal.md >/tmp/goal-with-codex-test-1.out
test -f feature.txt
test -f .goal-with-codex/state/evidence-latest.json
jq -e '.schema == "goal-with-codex.evidence.v1"' .goal-with-codex/state/evidence-latest.json >/dev/null
jq -e '.status == "awaiting_claude_review"' .goal-with-codex/state/evidence-latest.json >/dev/null
jq -e '.changed_files | index("feature.txt")' .goal-with-codex/state/evidence-latest.json >/dev/null
jq -e '.iteration == 1' .goal-with-codex/state.json >/dev/null

"$PLUGIN_BIN" run >/tmp/goal-with-codex-test-2.out
jq -e '.iteration == 2' .goal-with-codex/state.json >/dev/null
jq -e '.codex_action == "task_resume"' .goal-with-codex/state/evidence-latest.json >/dev/null
grep -q -- "--resume-last" "$CODEX_STUB_ARGS_LOG"
if grep -q "do-not-run" /tmp/goal-with-codex-test-1.out /tmp/goal-with-codex-test-2.out; then
  echo "shell-looking goal text leaked to command output" >&2
  exit 1
fi

"$PLUGIN_BIN" status >/tmp/goal-with-codex-status.out
grep -q "goal-with-codex status" /tmp/goal-with-codex-status.out

WORK_ARGS="$TMP_DIR/work-args"
mkdir -p "$WORK_ARGS"
cd "$WORK_ARGS"
git init -q
git config user.email test@example.com
git config user.name "Test User"
printf '# raw args fixture\n' > README.md
git add README.md
git commit -qm "initial"

RAW_GOAL='Please add raw argument goal support. $(do-not-run-raw)'
"$PLUGIN_BIN" run "$RAW_GOAL" >/tmp/goal-with-codex-test-raw-args.out
test -f .goal-with-codex/request/goal.md
jq -e --arg goal "$RAW_GOAL" '.user_goal == $goal and .technical_goal == $goal' .goal-with-codex/state.json >/dev/null
jq -e '.iteration == 1' .goal-with-codex/state.json >/dev/null
jq -e '.status == "awaiting_claude_review"' .goal-with-codex/state/evidence-latest.json >/dev/null
if grep -q "do-not-run-raw" /tmp/goal-with-codex-test-raw-args.out; then
  echo "shell-looking raw goal text leaked to command output" >&2
  exit 1
fi

WORK_NOCHANGE="$TMP_DIR/work-nochange"
mkdir -p "$WORK_NOCHANGE"
cd "$WORK_NOCHANGE"
git init -q
git config user.email test@example.com
git config user.name "Test User"
printf '# no change fixture\n' > README.md
git add README.md
git commit -qm "initial"

CODEX_STUB_NO_WRITE=1 "$PLUGIN_BIN" run "Verify no-op goal handling" >/tmp/goal-with-codex-test-nochange.out
jq -e '.changed_files == []' .goal-with-codex/state/evidence-latest.json >/dev/null
jq -e '.status == "awaiting_claude_review"' .goal-with-codex/state/evidence-latest.json >/dev/null

WORK_EMPTY="$TMP_DIR/work-empty"
mkdir -p "$WORK_EMPTY"
cd "$WORK_EMPTY"
git init -q
git config user.email test@example.com
git config user.name "Test User"
printf '# empty arg fixture\n' > README.md
git add README.md
git commit -qm "initial"

if "$PLUGIN_BIN" run "" >/tmp/goal-with-codex-test-empty.out 2>/tmp/goal-with-codex-test-empty.err; then
  echo "empty goal text unexpectedly started a new run" >&2
  exit 1
fi
grep -q "No active goal" /tmp/goal-with-codex-test-empty.err
test ! -f .goal-with-codex/state.json

echo "goal-with-codex workflow stub verification passed"
