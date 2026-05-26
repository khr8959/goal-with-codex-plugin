#!/bin/bash
# Stub verification for Issue #22 behavior.
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

assert_file_exists() {
  [ -f "$1" ] || fail "missing file: $1"
}

assert_file_absent() {
  [ ! -f "$1" ] || fail "unexpected file exists: $1"
}

make_fake_codex_root() {
  local dir="$1"
  mkdir -p "$dir/scripts"
  cat > "$dir/scripts/codex-companion.mjs" <<'EOF'
import fs from "node:fs";
const prompt = process.argv.slice(2).join("\n");
if (process.env.CODEX_STUB_PROMPT_FILE) {
  fs.writeFileSync(process.env.CODEX_STUB_PROMPT_FILE, prompt);
}
process.stdout.write(process.env.CODEX_STUB_OUTPUT || "{}");
EOF
}

make_goal_dual_state() {
  local eval_cmd_json="$1"
  local codex_root="$2"
  mkdir -p .goal-dual/state .goal-dual/logs
  printf '%s\n' "# goal" > .goal-dual/goal.md
  printf '%s\n' "- done" > .goal-dual/state/acceptance-criteria.md
  printf '%s\n' "0" > .goal-dual/state/eval-exit.txt
  printf '%s\n' "PASS" > .goal-dual/state/eval-output.log
  jq -n \
    --argjson eval_cmd "$eval_cmd_json" \
    --arg codex_root "$codex_root" \
    --arg goal_root "$ROOT/plugins/goal-dual" \
    '{
      iteration: 1,
      eval_cmd: $eval_cmd,
      no_git: true,
      codex_plugin_root: $codex_root,
      goal_dual_plugin_root: $goal_root,
      pivot_requested: false
    }' > .goal-dual/state.json
}

run_codex_evaluate_case() {
  local eval_cmd_json="$1"
  local confidence="$2"
  local expected_verdict="$3"
  local expect_final_flag="$4"
  local expect_no_eval_rule="$5"

  local tmp fake prompt_file
  tmp=$(mktemp -d)
  fake="$tmp/fake-codex"
  prompt_file="$tmp/prompt.txt"
  make_fake_codex_root "$fake"
  (
    cd "$tmp"
    make_goal_dual_state "$eval_cmd_json" "$fake"
    CODEX_STUB_PROMPT_FILE="$prompt_file" \
    CODEX_STUB_OUTPUT="{\"verdict\":\"complete\",\"confidence\":${confidence},\"evidence\":[\"stub\"],\"missing\":[],\"next_action\":null}" \
      bash "$SCRIPTS/codex-evaluate.sh"

    local verdict
    verdict=$(jq -r '.verdict' .goal-dual/state/evaluations/codex-1.json)
    assert_eq "$expected_verdict" "$verdict" "codex-evaluate verdict confidence=${confidence}"

    if [ "$expect_final_flag" = "true" ]; then
      assert_file_exists .goal-dual/CLAUDE_FINAL_CHECK_NEEDED
    else
      assert_file_absent .goal-dual/CLAUDE_FINAL_CHECK_NEEDED
    fi

    if [ "$expect_no_eval_rule" = "true" ]; then
      grep -q "complete と判定する confidence は 0.8 以上" "$prompt_file" \
        || fail "no-eval confidence rule was not injected"
    else
      ! grep -q "eval-cmd が設定されていないため" "$prompt_file" \
        || fail "no-eval confidence rule leaked into eval-cmd case"
    fi
  )
  rm -rf "$tmp"
}

verify_consecutive_count() {
  local tmp
  tmp=$(mktemp -d)
  (
    cd "$tmp"
    mkdir -p .goal-dual/state/evaluations
    # shellcheck disable=SC1090
    source "$SCRIPTS/lib.sh"
    assert_eq "0" "$(consecutive_same_verdict_count)" "empty consecutive count"
    printf '%s\n' '{"verdict":"incomplete"}' > .goal-dual/state/evaluations/synthesized-1.json
    assert_eq "1" "$(consecutive_same_verdict_count)" "single consecutive count"
    printf '%s\n' '{"verdict":"incomplete"}' > .goal-dual/state/evaluations/synthesized-2.json
    assert_eq "2" "$(consecutive_same_verdict_count)" "two consecutive count"
    printf '%s\n' '{"verdict":"complete"}' > .goal-dual/state/evaluations/synthesized-3.json
    assert_eq "1" "$(consecutive_same_verdict_count)" "count resets on verdict change"
    printf '%s\n' '{"verdict":"complete"}' > .goal-dual/state/evaluations/synthesized-4.json
    printf '%s\n' '{"verdict":"complete"}' > .goal-dual/state/evaluations/synthesized-5.json
    printf '%s\n' '{"verdict":"complete"}' > .goal-dual/state/evaluations/synthesized-6.json
    assert_eq "3" "$(GOAL_DUAL_STAGNATION_THRESHOLD=3 consecutive_same_verdict_count)" "count is capped at threshold"
  )
  rm -rf "$tmp"
}

verify_safety_pivot_and_stagnant() {
  local tmp
  tmp=$(mktemp -d)
  (
    cd "$tmp"
    mkdir -p .goal-dual/state/evaluations
    jq -n '{codex_failed_count:0, codex_work_no_change_count:0, pivot_requested:false}' > .goal-dual/state.json
    : > .goal-dual/progress.txt
    printf '%s\n' '{"verdict":"incomplete"}' > .goal-dual/state/evaluations/synthesized-1.json
    printf '%s\n' '{"verdict":"incomplete"}' > .goal-dual/state/evaluations/synthesized-2.json
    bash "$SCRIPTS/safety.sh" 2 >/tmp/goal-dual-safety-issue22.out 2>/tmp/goal-dual-safety-issue22.err
    assert_eq "true" "$(jq -r '.pivot_requested' .goal-dual/state.json)" "pivot requested at threshold minus one"
    grep -q "pivot_requested: true" .goal-dual/progress.txt \
      || fail "pivot warning was not written to progress"

    printf '%s\n' '{"verdict":"incomplete"}' > .goal-dual/state/evaluations/synthesized-3.json
    set +e
    bash "$SCRIPTS/safety.sh" 3 >/tmp/goal-dual-safety-issue22-stop.out 2>/tmp/goal-dual-safety-issue22-stop.err
    local status=$?
    set -e
    assert_eq "10" "$status" "STOP_STAGNANT still fires at threshold"
  )
  rm -rf "$tmp"
}

verify_codex_work_pivot_reset() {
  local tmp fake prompt_file
  tmp=$(mktemp -d)
  fake="$tmp/fake-codex"
  prompt_file="$tmp/prompt.txt"
  make_fake_codex_root "$fake"
  (
    cd "$tmp"
    mkdir -p .goal-dual/logs
    printf '%s\n' "# goal" > .goal-dual/goal.md
    jq -n --arg codex_root "$fake" '{iteration:1, codex_plugin_root:$codex_root, pivot_requested:true}' > .goal-dual/state.json
    CODEX_STUB_PROMPT_FILE="$prompt_file" \
    CODEX_STUB_OUTPUT='{"status":"implemented","changed_files":[],"summary":"stub","self_review":"stub","risk":"low","next_action":"stub"}' \
      bash "$SCRIPTS/codex-work.sh" .goal-dual >/tmp/goal-dual-codex-work-issue22.out
    grep -q "前回までと全く異なるアプローチで実装してください" "$prompt_file" \
      || fail "pivot instruction was not injected into codex-work prompt"
    assert_eq "false" "$(jq -r '.pivot_requested' .goal-dual/state.json)" "pivot requested reset after codex-work"
  )
  rm -rf "$tmp"
}

run_codex_evaluate_case "null" "0.79" "incomplete" "false" "true"
run_codex_evaluate_case "null" "0.8" "complete" "true" "true"
run_codex_evaluate_case '"npm test"' "0.79" "complete" "true" "false"
verify_consecutive_count
verify_safety_pivot_and_stagnant
verify_codex_work_pivot_reset

echo "PASS issue22 stubs"
