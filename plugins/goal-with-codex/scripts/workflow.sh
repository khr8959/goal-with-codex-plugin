#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/eval-registry.sh"

usage() {
  cat <<'EOF'
goal-with-codex run [--goal-file <path>] [goal text]

Start or continue a goal-shaped workflow that routes implementation and review
through the official codex@openai-codex plugin.
EOF
}

GOAL_FILE=""
GOAL_TEXT_ARGS=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    --goal-file)
      GOAL_FILE="${2:-}"
      if [ -z "$GOAL_FILE" ]; then
        echo "--goal-file requires a path" >&2
        exit 2
      fi
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    --)
      shift
      while [ "$#" -gt 0 ]; do GOAL_TEXT_ARGS+=("$1"); shift; done
      ;;
    *)
      GOAL_TEXT_ARGS+=("$1")
      shift
      ;;
  esac
done

goal_text_from_args() {
  local joined=""
  local part
  for part in "${GOAL_TEXT_ARGS[@]}"; do
    if [ -n "$joined" ]; then joined+=" "; fi
    joined+="$part"
  done
  printf '%s' "$joined"
}

goal_contract_text() {
  if [ -n "$GOAL_FILE" ]; then
    if [ ! -f "$GOAL_FILE" ]; then
      echo "goal file not found: $GOAL_FILE" >&2
      exit 2
    fi
    cat "$GOAL_FILE"
    return
  fi
  goal_text_from_args
}

new_goal_requested() {
  [ -n "$GOAL_FILE" ] && return 0
  [ "${#GOAL_TEXT_ARGS[@]}" -gt 0 ] && return 0
  return 1
}

read_section() {
  local heading="$1"
  local file="$2"
  awk -v wanted="$heading" '
    BEGIN { in_section=0 }
    /^#[[:space:]]+/ {
      title=$0
      sub(/^#[[:space:]]+/, "", title)
      in_section=(tolower(title)==tolower(wanted))
      next
    }
    in_section { print }
  ' "$file" | sed '/^[[:space:]]*$/d'
}

initialize_state() {
  local contract_file="$1"
  local codex_root="$2"
  local dirty
  dirty=$(gwc_dirty_check)
  if [ -n "$dirty" ]; then
    echo "Working tree has existing changes. Commit, stash, or inspect them before starting a new goal." >&2
    echo "$dirty" >&2
    exit 3
  fi

  mkdir -p "$GWC_DIR/request" "$GWC_DIR/state" "$GWC_DIR/logs"
  gwc_detect_eval_cmd

  local user_goal technical_goal acceptance constraints non_goals branch
  user_goal=$(read_section "User Goal" "$contract_file")
  technical_goal=$(read_section "Technical Goal" "$contract_file")
  acceptance=$(read_section "Acceptance Criteria" "$contract_file")
  constraints=$(read_section "Constraints" "$contract_file")
  non_goals=$(read_section "Non-goals" "$contract_file")
  if [ -z "$user_goal" ]; then user_goal=$(cat "$contract_file"); fi
  if [ -z "$technical_goal" ]; then technical_goal="$user_goal"; fi
  if [ -z "$acceptance" ]; then acceptance="- The requested behavior is implemented without unrelated changes."; fi
  branch=$(git branch --show-current 2>/dev/null || true)

  jq -n \
    --arg schema "goal-with-codex.state.v1" \
    --arg created_at "$(gwc_now_utc)" \
    --arg user_goal "$user_goal" \
    --arg technical_goal "$technical_goal" \
    --arg acceptance_criteria "$acceptance" \
    --arg constraints "$constraints" \
    --arg non_goals "$non_goals" \
    --arg eval_cmd "$EVAL_CMD" \
    --arg eval_cmd_source "$EVAL_CMD_SOURCE" \
    --arg codex_plugin_root "$codex_root" \
    --arg goal_with_codex_plugin_root "$PLUGIN_ROOT" \
    --arg branch "$branch" \
    '{
      schema:$schema,
      created_at:$created_at,
      updated_at:$created_at,
      completed:false,
      iteration:0,
      loop_phase:"initialized",
      stop_reason:null,
      user_goal:$user_goal,
      technical_goal:$technical_goal,
      acceptance_criteria:$acceptance_criteria,
      constraints:$constraints,
      non_goals:$non_goals,
      eval_cmd:$eval_cmd,
      eval_cmd_source:$eval_cmd_source,
      codex_plugin_root:$codex_plugin_root,
      goal_with_codex_plugin_root:$goal_with_codex_plugin_root,
      branch:$branch,
      routing_policy_version:1,
      last_action:null
    }' > "$GWC_STATE"
  gwc_event "goal_started" "$(jq -n --arg goal "$technical_goal" '{goal:$goal}')"
}

build_codex_prompt() {
  local prompt_file="$1"
  local iteration="$2"
  local trigger="$3"
  local eval_excerpt="$4"
  local previous_evidence="$5"
  local technical_goal acceptance constraints non_goals user_goal
  user_goal=$(gwc_state_get user_goal)
  technical_goal=$(gwc_state_get technical_goal)
  acceptance=$(gwc_state_get acceptance_criteria)
  constraints=$(gwc_state_get constraints)
  non_goals=$(gwc_state_get non_goals)

  cat > "$prompt_file" <<EOF
<goal_with_codex_task>
You are Codex working inside a Claude Code goal workflow. Implement exactly one bounded step toward the technical goal.

User goal:
$user_goal

Technical goal:
$technical_goal

Acceptance criteria:
$acceptance

Constraints:
$constraints

Non-goals:
$non_goals

Routing context:
- Iteration: $iteration
- Trigger: $trigger
- You may edit files because this call is made with --write.
- Keep the change as small as possible while making real progress.
- Do not commit, push, rename the repository, or install global tools.
- If the task is already complete, verify it and say so without making unrelated edits.

Previous evidence:
$previous_evidence

Latest eval excerpt:
$eval_excerpt

Return a concise final message with these headings:
Summary
Changed files
Verification
Remaining work
Risk
</goal_with_codex_task>
EOF
}

run_codex_task() {
  local codex_root="$1"
  local iteration="$2"
  local trigger="$3"
  local prompt_file="$GWC_DIR/state/codex-prompt-${iteration}.md"
  local output_file="$GWC_DIR/state/codex-task-${iteration}.json"
  local eval_excerpt previous_evidence
  eval_excerpt=$(cat "$GWC_DIR/state/eval-output.log" 2>/dev/null || true)
  previous_evidence=$(jq -c . "$GWC_DIR/state/evidence-latest.json" 2>/dev/null || true)
  build_codex_prompt "$prompt_file" "$iteration" "$trigger" "$eval_excerpt" "$previous_evidence"

  local args=( "$codex_root/scripts/codex-companion.mjs" task --write --json --prompt-file "$prompt_file" )
  if [ "$iteration" -gt 1 ]; then
    args+=( --resume-last )
  fi

  gwc_event "codex_task_started" "$(jq -n --argjson iteration "$iteration" --arg trigger "$trigger" '{iteration:$iteration,trigger:$trigger}')"
  local exit_code=0
  if node "${args[@]}" > "$output_file" 2>"$GWC_DIR/logs/codex-task-${iteration}.stderr.log"; then
    exit_code=0
  else
    exit_code=$?
  fi
  gwc_event "codex_task_finished" "$(jq -n --argjson iteration "$iteration" --argjson exit_code "$exit_code" '{iteration:$iteration,exit_code:$exit_code}')"
  echo "$exit_code" > "$GWC_DIR/state/codex-task-exit.txt"
}

run_codex_review() {
  local codex_root="$1"
  local iteration="$2"
  local risk="$3"
  local review_file="$GWC_DIR/state/codex-review-${iteration}.json"
  local review_exit=0
  if node "$codex_root/scripts/codex-companion.mjs" review --wait --json --scope working-tree > "$review_file" 2>"$GWC_DIR/logs/codex-review-${iteration}.stderr.log"; then
    review_exit=0
  else
    review_exit=$?
  fi
  echo "$review_exit" > "$GWC_DIR/state/codex-review-exit.txt"
  gwc_event "codex_review_finished" "$(jq -n --argjson iteration "$iteration" --argjson exit_code "$review_exit" '{iteration:$iteration,exit_code:$exit_code}')"

  if [ "$risk" = "high" ]; then
    local adv_file="$GWC_DIR/state/codex-adversarial-review-${iteration}.json"
    local adv_exit=0
    if node "$codex_root/scripts/codex-companion.mjs" adversarial-review --wait --json --scope working-tree "Challenge whether this goal step is safe, minimal, and aligned with the acceptance criteria." > "$adv_file" 2>"$GWC_DIR/logs/codex-adversarial-review-${iteration}.stderr.log"; then
      adv_exit=0
    else
      adv_exit=$?
    fi
    echo "$adv_exit" > "$GWC_DIR/state/codex-adversarial-review-exit.txt"
    gwc_event "codex_adversarial_review_finished" "$(jq -n --argjson iteration "$iteration" --argjson exit_code "$adv_exit" '{iteration:$iteration,exit_code:$exit_code}')"
  fi
}

write_evidence() {
  local iteration="$1"
  local trigger="$2"
  local risk="$3"
  local changed_files="$4"
  local codex_task_file="$GWC_DIR/state/codex-task-${iteration}.json"
  local review_file="$GWC_DIR/state/codex-review-${iteration}.json"
  local adv_file="$GWC_DIR/state/codex-adversarial-review-${iteration}.json"
  local eval_exit eval_label status recommendation task_exit review_exit adv_exit
  eval_exit=$(cat "$GWC_DIR/state/eval-exit.txt" 2>/dev/null || true)
  task_exit=$(cat "$GWC_DIR/state/codex-task-exit.txt" 2>/dev/null || echo 1)
  review_exit=$(cat "$GWC_DIR/state/codex-review-exit.txt" 2>/dev/null || true)
  adv_exit=$(cat "$GWC_DIR/state/codex-adversarial-review-exit.txt" 2>/dev/null || true)
  if [ -z "$eval_exit" ]; then
    eval_label="skipped"
  elif [ "$eval_exit" = "0" ]; then
    eval_label="passed"
  else
    eval_label="failed"
  fi

  if [ "$task_exit" != "0" ]; then
    status="stopped"
    recommendation="inspect_codex_error"
  elif [ "$eval_label" = "failed" ]; then
    status="needs_fix"
    recommendation="run_goal_with_codex_again"
  elif [ "$review_exit" != "" ] && [ "$review_exit" != "0" ]; then
    status="awaiting_claude_review"
    recommendation="read_review_then_decide"
  elif [ "$adv_exit" != "" ] && [ "$adv_exit" != "0" ]; then
    status="awaiting_claude_review"
    recommendation="read_adversarial_review_then_decide"
  else
    status="awaiting_claude_review"
    recommendation="claude_acceptance_check"
  fi

  jq -n \
    --arg schema "goal-with-codex.evidence.v1" \
    --arg created_at "$(gwc_now_utc)" \
    --arg status "$status" \
    --arg recommendation "$recommendation" \
    --arg trigger "$trigger" \
    --arg risk "$risk" \
    --argjson iteration "$iteration" \
    --arg eval_cmd "$(gwc_state_get eval_cmd)" \
    --arg eval_label "$eval_label" \
    --arg eval_exit_code "${eval_exit:-null}" \
    --arg eval_output_ref "$GWC_DIR/state/eval-output.log" \
    --arg codex_task_ref "$codex_task_file" \
    --arg review_ref "$review_file" \
    --arg adversarial_review_ref "$adv_file" \
    --argjson changed_files "$changed_files" \
    --slurpfile codex_task "$codex_task_file" \
    '{
      schema:$schema,
      created_at:$created_at,
      iteration:$iteration,
      status:$status,
      recommendation:$recommendation,
      trigger:$trigger,
      codex_action:(if $iteration == 1 then "task" else "task_resume" end),
      codex:{
        risk:$risk,
        task_ref:$codex_task_ref,
        task:($codex_task[0] // null)
      },
      review:{
        review_ref:$review_ref,
        adversarial_review_ref:$adversarial_review_ref
      },
      eval:{
        command:$eval_cmd,
        label:$eval_label,
        exit_code:$eval_exit_code,
        output_ref:$eval_output_ref
      },
      changed_files:$changed_files,
      next_commands:[
        "goal-with-codex status",
        "goal-with-codex run"
      ]
    }' > "$GWC_DIR/state/evidence-latest.json"

  gwc_state_set updated_at "$(gwc_now_utc)"
  gwc_state_set iteration "$iteration"
  gwc_state_set loop_phase "$status"
  gwc_state_set last_action "$recommendation"
  gwc_event "evidence_written" "$(jq -n --arg status "$status" --arg recommendation "$recommendation" '{status:$status,recommendation:$recommendation}')"
}

main() {
  local codex_root
  codex_root=$(gwc_require_codex_plugin_root)
  mkdir -p "$GWC_DIR/request" "$GWC_DIR/state" "$GWC_DIR/logs"

  if new_goal_requested; then
    local tmp_contract="$GWC_DIR/request/goal.md"
    goal_contract_text > "$tmp_contract"
    initialize_state "$tmp_contract" "$codex_root"
  elif [ ! -f "$GWC_STATE" ]; then
    echo "No active goal. Start with: goal-with-codex run <goal>" >&2
    exit 2
  fi

  local current_iteration iteration trigger previous_status
  current_iteration=$(jq -r '.iteration // 0' "$GWC_STATE")
  iteration=$((current_iteration + 1))
  previous_status=$(jq -r '.loop_phase // "initialized"' "$GWC_STATE")
  case "$previous_status" in
    needs_fix) trigger="failing_eval_fix" ;;
    awaiting_claude_review) trigger="continue_after_review" ;;
    *) trigger="implementation" ;;
  esac

  gwc_progress "iteration $iteration started" <<EOF
trigger: $trigger
technical_goal: $(gwc_state_get technical_goal)
EOF

  run_codex_task "$codex_root" "$iteration" "$trigger"
  bash "$SCRIPT_DIR/run-eval.sh" "$iteration" >/dev/null || true

  local changed_files changed_count risk eval_exit
  changed_files=$(gwc_changed_files_json)
  changed_count=$(printf '%s' "$changed_files" | jq 'length')
  risk=$(gwc_risk_level "$(gwc_state_get technical_goal)" "$changed_count")
  eval_exit=$(cat "$GWC_DIR/state/eval-exit.txt" 2>/dev/null || true)
  if [ -z "$eval_exit" ] || [ "$eval_exit" = "0" ]; then
    run_codex_review "$codex_root" "$iteration" "$risk"
  fi

  write_evidence "$iteration" "$trigger" "$risk" "$changed_files"

  jq -r '"goal-with-codex: " + .status + " (" + .recommendation + ")\nEvidence: .goal-with-codex/state/evidence-latest.json"' "$GWC_DIR/state/evidence-latest.json"
}

main "$@"
