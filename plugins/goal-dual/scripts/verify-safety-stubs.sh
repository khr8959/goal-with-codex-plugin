#!/bin/bash
# goal-dual/scripts/verify-safety-stubs.sh — 安全側デフォルトの軽量回帰テスト
set -euo pipefail

SCRIPTS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPTS/lib.sh"

fail() {
  echo "FAIL $1" >&2
  exit 1
}

assert_eq() {
  local expected="$1" actual="$2" label="$3"
  [ "$expected" = "$actual" ] || fail "$label: expected '$expected', got '$actual'"
}

verify_redaction() {
  local out
  out=$(printf '%s\n' \
    'OPENAI_API_KEY=sk-test12345678901234567890' \
    'GITHUB_TOKEN=ghp_1234567890abcdefghijklmnop' \
    'Authorization: Bearer aaa.bbb.cccccccccccccccccccccccccc' \
    'password=super-secret-value' \
    | redact_for_llm)
  echo "$out" | grep -q 'sk-test12345678901234567890' && fail "OpenAI key was not redacted"
  echo "$out" | grep -q 'ghp_1234567890abcdefghijklmnop' && fail "GitHub token was not redacted"
  echo "$out" | grep -q '\[REDACTED_JWT\]' || fail "JWT was not redacted"
  echo "$out" | grep -q 'password=\[REDACTED\]' || fail "password assignment was not redacted"
}

verify_commit_defaults() {
  local tmp
  tmp=$(mktemp -d)
  (
    cd "$tmp"
    git init -q
    git config user.email test@example.com
    git config user.name "goal-dual test"
    printf '%s\n' initial > file.txt
    git add file.txt
    git commit -q -m initial
    mkdir -p .goal-dual/state/evaluations
    jq -n '{no_git:false,goal_text:"安全デフォルト確認",last_synthesized_verdict:"incomplete"}' > .goal-dual/state.json
    printf '%s\n' '# progress' > .goal-dual/progress.txt
    printf '%s\n' changed > file.txt
    "$SCRIPTS/commit-iter.sh" 1 wip >/tmp/goal-dual-verify-commit.out
    assert_eq "1" "$(git rev-list --count HEAD)" "WIP commit should be off by default"
    "$SCRIPTS/commit-iter.sh" 1 pass >/tmp/goal-dual-verify-final-commit.out
    assert_eq "1" "$(git rev-list --count HEAD)" "final commit should be off by default"
  )
  rm -rf "$tmp"
}

verify_doctor_runs() {
  bash "$SCRIPTS/doctor.sh" >/tmp/goal-dual-doctor.out || fail "doctor should run"
  grep -q "scope violations stop by default" /tmp/goal-dual-doctor.out \
    || fail "doctor did not report scope enforce default"
}

verify_redaction
verify_commit_defaults
verify_doctor_runs

echo "PASS safety stubs"
