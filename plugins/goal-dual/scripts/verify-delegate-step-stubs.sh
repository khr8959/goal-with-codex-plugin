#!/bin/bash
# Stub verification for the v2 delegate-step flow.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
SCRIPTS="$ROOT/plugins/goal-dual/scripts"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_eq() {
  local expected="$1"
  local actual="$2"
  local label="$3"
  [ "$expected" = "$actual" ] || fail "$label: expected '$expected', got '$actual'"
}

make_fake_codex_root() {
  local dir="$1"
  mkdir -p "$dir/scripts"
  cat > "$dir/scripts/codex-companion.mjs" <<'EOF'
import fs from "node:fs";

if (process.env.CODEX_STUB_WRITE_FILE) {
  fs.writeFileSync(process.env.CODEX_STUB_WRITE_FILE, process.env.CODEX_STUB_WRITE_BODY || "changed\n");
}

process.stdout.write(process.env.CODEX_STUB_OUTPUT || JSON.stringify({
  schema: "goal-dual.work-result.v1",
  status: "implemented",
  changed_files: [process.env.CODEX_STUB_WRITE_FILE || "changed.txt"],
  summary: "stub implementation",
  self_review: "stub reviewed",
  risk: "low",
  next_action: "Claude should review evidence"
}));
EOF
}

make_fake_path() {
  local dir="$1"
  mkdir -p "$dir"
  cat > "$dir/codex" <<'EOF'
#!/bin/bash
echo "codex stub"
EOF
  chmod +x "$dir/codex"
}

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

fake_codex="$tmp/fake-codex"
fake_bin="$tmp/bin"
repo="$tmp/repo"
make_fake_codex_root "$fake_codex"
make_fake_path "$fake_bin"

mkdir -p "$repo"
(
  cd "$repo"
  git init -b main >/dev/null 2>&1
  git config user.name "goal-dual test"
  git config user.email "goal-dual@example.invalid"
  printf '%s\n' "# demo" > README.md
  git add README.md
  git commit -m "initial" >/dev/null 2>&1

  PATH="$fake_bin:$PATH" \
  CODEX_PLUGIN_ROOT="$fake_codex" \
  CODEX_STUB_WRITE_FILE="feature.txt" \
  bash "$SCRIPTS/delegate-step.sh" "Add feature file" >/tmp/goal-dual-delegate-step-1.out

  assert_eq "1" "$(jq -r '.iteration' .goal-dual/state/evidence-latest.json)" "first iteration"
  assert_eq "awaiting_claude_review" "$(jq -r '.status' .goal-dual/state/evidence-latest.json)" "first evidence status"
  jq -e '.changed_files | index("feature.txt")' .goal-dual/state/evidence-latest.json >/dev/null \
    || fail "first evidence did not include feature.txt"

  # The second step must continue with the previous uncommitted Codex change.
  # This is the main UX fix: dirty state after a Codex step is expected and
  # should not block continuation of the same goal.
  PATH="$fake_bin:$PATH" \
  CODEX_PLUGIN_ROOT="$fake_codex" \
  CODEX_STUB_WRITE_FILE="feature-2.txt" \
  bash "$SCRIPTS/delegate-step.sh" >/tmp/goal-dual-delegate-step-2.out

  assert_eq "2" "$(jq -r '.iteration' .goal-dual/state/evidence-latest.json)" "second iteration"
  assert_eq "awaiting_claude_review" "$(jq -r '.status' .goal-dual/state/evidence-latest.json)" "second evidence status"
  [ "$(jq -r '.stop_reason // empty' .goal-dual/state.json)" = "" ] || fail "second step unexpectedly stopped"
)

echo "PASS delegate-step stubs"
