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

verify_dashboard_api() {
  local tmp port server_pid
  tmp=$(mktemp -d)
  port=48762
  (
    cd "$tmp"
    mkdir -p .goal-dual/state/evaluations
    jq -n '{goal_text:"dashboard test",iteration:1,completed:false,loop_phase:"iterating",scope_mode:"enforce",review_level:"standard"}' > .goal-dual/state.json
    printf '%s\n' '{"type":"run_started","time":"2026-01-01T00:00:00Z"}' > .goal-dual/events.jsonl
    node "$SCRIPTS/dashboard-server.mjs" --host=127.0.0.1 --port="$port" --root="$tmp" >/tmp/goal-dual-dashboard.out 2>&1 &
    server_pid=$!
    for _ in 1 2 3 4 5; do
      if curl -fsS "http://127.0.0.1:${port}/api/state" >/tmp/goal-dual-dashboard-state.json 2>/dev/null; then
        break
      fi
      sleep 1
    done
    kill "$server_pid" >/dev/null 2>&1 || true
    wait "$server_pid" 2>/dev/null || true
    if grep -q 'listen EPERM' /tmp/goal-dual-dashboard.out 2>/dev/null; then
      echo "SKIP dashboard API listen test（environment disallows localhost listen）"
      exit 0
    fi
    jq -e '.has_run == true and .state.goal_text == "dashboard test"' /tmp/goal-dual-dashboard-state.json >/dev/null \
      || fail "dashboard API did not return state"
  )
  rm -rf "$tmp"
}

verify_redaction
verify_commit_defaults
verify_doctor_runs
verify_dashboard_api

echo "PASS safety stubs"
