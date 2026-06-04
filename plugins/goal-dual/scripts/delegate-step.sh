#!/bin/bash
# goal-dual/scripts/delegate-step.sh
# Claude /goal の反復内で Codex に「実装1ステップ」だけを委譲する。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib.sh"

STATE=".goal-dual/state.json"
EVIDENCE=".goal-dual/state/evidence-latest.json"

now_utc() { date -u +%Y-%m-%dT%H:%M:%SZ; }

print_json_summary() {
  if [ -f "$EVIDENCE" ]; then
    jq -r '
      "=== goal-dual delegated step ===",
      "status       : " + (.status // "unknown"),
      "iteration    : " + ((.iteration // 0) | tostring),
      "codex        : " + (.codex.status // "unknown") + " / risk=" + (.codex.risk // "unknown"),
      "eval         : " + (.eval.label // "not configured"),
      "changed files: " + (((.changed_files // []) | length) | tostring),
      "next         : " + (.next_action // "Claude reviews the evidence and decides the next /goal step."),
      "",
      "Evidence     : .goal-dual/state/evidence-latest.json",
      "Status       : /goal-dual:status",
      "Dashboard    : /goal-dual:dashboard"
    ' "$EVIDENCE"
  fi
}

ensure_run_initialized() {
  local goal_text="$*"
  local init_status=0

  if [ ! -f "$STATE" ]; then
    if [ -z "$goal_text" ]; then
      echo "ゴールが未指定です: /goal-dual:run <ゴール>" >&2
      exit 1
    fi
    bash "$SCRIPT_DIR/init.sh" "$goal_text" || init_status=$?
    if [ "$init_status" -ne 0 ] && [ "$init_status" -ne 2 ]; then
      exit "$init_status"
    fi
  elif [ -n "$goal_text" ]; then
    local completed
    completed=$(jq -r '.completed // false' "$STATE" 2>/dev/null || echo "false")
    if [ "$completed" != "true" ]; then
      echo "既存の goal-dual 実行中です。続ける場合は引数なしで /goal-dual:run を実行してください。" >&2
      echo "別ゴールを始める場合は .goal-dual/ を確認・退避してから再実行してください。" >&2
      exit 1
    fi
    bash "$SCRIPT_DIR/init.sh" "$goal_text" || init_status=$?
    if [ "$init_status" -ne 0 ] && [ "$init_status" -ne 2 ]; then
      exit "$init_status"
    fi
  fi

  mkdir -p .goal-dual/state/evaluations .goal-dual/logs
}

ensure_minimal_acceptance() {
  if [ -f .goal-dual/state/acceptance-criteria.md ]; then
    return
  fi
  cat > .goal-dual/state/acceptance-criteria.md <<'EOF'
## 完了条件

- ゴール本文で依頼された変更が実装されている
- 検出された評価コマンドがある場合、その評価が成功する
- 変更範囲外や高リスクな変更が必要な場合は、人間に判断を返す
EOF
}

write_evidence() {
  local status="$1"
  local next_action="$2"
  local iter="$3"
  local eval_exit="$4"
  local eval_label="$5"
  local stop_reason="${6:-}"
  local codex_result=".goal-dual/codex-work-result.json"
  local fallback_codex=""
  local changed_file_json

  if [ ! -f "$codex_result" ]; then
    fallback_codex=$(mktemp)
    jq -n '{
      schema: "goal-dual.work-result.v1",
      status: "blocked",
      changed_files: [],
      summary: "Codex work did not run",
      self_review: "",
      risk: "high",
      next_action: "Check the stop reason before delegating again"
    }' > "$fallback_codex"
    codex_result="$fallback_codex"
  fi

  changed_file_json=$(git status --porcelain 2>/dev/null \
    | grep -v -E '^\?\? \.goal-dual/|^.. \.goal-dual/' \
    | sed 's/^...//' \
    | jq -R . \
    | jq -s 'unique' 2>/dev/null || echo "[]")

  jq -n \
    --arg schema "goal-dual.evidence.v1" \
    --arg status "$status" \
    --argjson iteration "$iter" \
    --arg generated_at "$(now_utc)" \
    --arg stop_reason "$stop_reason" \
    --arg eval_exit "$eval_exit" \
    --arg eval_label "$eval_label" \
    --arg next_action "$next_action" \
    --argjson changed_files "$changed_file_json" \
    --slurpfile codex "$codex_result" \
    '{
      schema: $schema,
      status: $status,
      iteration: $iteration,
      generated_at: $generated_at,
      stop_reason: (if $stop_reason == "" then null else $stop_reason end),
      codex: ($codex[0] // {
        status: "blocked",
        changed_files: [],
        summary: "Codex result is missing",
        self_review: "",
        risk: "high",
        next_action: "Codex result file should be inspected"
      }),
      eval: {
        exit_code: ($eval_exit | tonumber?),
        label: $eval_label,
        output_ref: ".goal-dual/state/eval-output.log"
      },
      changed_files: $changed_files,
      next_action: $next_action,
      claude_instruction: "Read this evidence only. Decide whether the official /goal loop should ask goal-dual to run another Codex step, mark the goal complete, or stop for the user."
    }' > "$EVIDENCE"

  [ -n "$fallback_codex" ] && rm -f "$fallback_codex"

  goal_dual_event "evidence_written" "$(jq -c '{iteration,status,stop_reason,next_action}' "$EVIDENCE")"
}

mark_state_after_step() {
  local iter="$1"
  local status="$2"
  local stop_reason="${3:-null}"
  state_set iteration "$iter"
  state_set last_updated_at "$(now_utc)"
  state_set last_step_status "$status"
  if [ "$stop_reason" = "null" ] || [ -z "$stop_reason" ]; then
    state_set completed false
    state_set stop_reason null
  else
    state_set completed true
    state_set stop_reason "$stop_reason"
  fi
}

ensure_run_initialized "$@"
ensure_minimal_acceptance

completed=$(jq -r '.completed // false' "$STATE")
if [ "$completed" = "true" ]; then
  print_json_summary
  exit 0
fi

current_iter=$(jq -r '.iteration // 0' "$STATE")

# 初回だけ開始前 dirty を hard-stop する。2回目以降は前ステップの Codex 変更を残したまま続行できる。
if [ "${current_iter:-0}" -eq 0 ]; then
  dirty=$(goal_dual_dirty_check)
  if [ -n "$dirty" ]; then
    mark_state_after_step 0 "stopped" "STOP_DIRTY"
    write_evidence "stopped" "作業ツリーに既存変更があります。確認してから再実行してください。" 0 "" "not run" "STOP_DIRTY"
    print_json_summary
    exit 0
  fi
fi

iter=$(( current_iter + 1 ))
state_set iteration "$iter"
state_set loop_phase "delegating_to_codex"
state_set last_updated_at "$(now_utc)"

codex_status=0
bash "$SCRIPT_DIR/codex-work.sh" .goal-dual || codex_status=$?

codex_result=".goal-dual/codex-work-result.json"
cw_status=$(jq -r '.status // "blocked"' "$codex_result" 2>/dev/null || echo "blocked")
cw_risk=$(jq -r '.risk // "high"' "$codex_result" 2>/dev/null || echo "high")
cw_next=$(jq -r '.next_action // "Codex result should be inspected."' "$codex_result" 2>/dev/null || echo "Codex result should be inspected.")

scope_status=0
bash "$SCRIPT_DIR/scope-check.sh" "$iter" >/dev/null 2>&1 || scope_status=$?
if [ "$scope_status" -eq 2 ]; then
  mark_state_after_step "$iter" "stopped" "STOP_SCOPE"
  write_evidence "stopped" "変更禁止範囲への変更が検出されました。scope-violations を確認してください。" "$iter" "" "not run" "STOP_SCOPE"
  print_json_summary
  exit 0
fi

if [ "$codex_status" -ne 0 ]; then
  mark_state_after_step "$iter" "stopped" "STOP_CODEX"
  write_evidence "stopped" "Codex委譲に失敗しました。ログを確認してください。" "$iter" "" "not run" "STOP_CODEX"
  print_json_summary
  exit 0
fi

if [ "$cw_status" = "blocked" ]; then
  mark_state_after_step "$iter" "stopped" "STOP_HUMAN"
  write_evidence "stopped" "$cw_next" "$iter" "" "not run" "STOP_HUMAN"
  print_json_summary
  exit 0
fi

if [ "$cw_risk" = "high" ] && [ "${GOAL_DUAL_ALLOW_HIGH_RISK:-0}" != "1" ]; then
  mark_state_after_step "$iter" "stopped" "STOP_HIGH_RISK"
  write_evidence "stopped" "Codexが high risk と判定しました。人間が差分を確認してください。" "$iter" "" "not run" "STOP_HIGH_RISK"
  print_json_summary
  exit 0
fi

bash "$SCRIPT_DIR/run-eval.sh" "$iter" || true
eval_exit=$(cat .goal-dual/state/eval-exit.txt 2>/dev/null || echo "")
if [ -z "$eval_exit" ]; then
  eval_label="not configured"
elif [ "$eval_exit" = "0" ]; then
  eval_label="passed"
else
  eval_label="failed"
fi

if [ "$eval_label" = "failed" ]; then
  mark_state_after_step "$iter" "needs_fix" ""
  write_evidence "needs_fix" "評価コマンドが失敗しています。次の /goal-dual:run でCodexに修正を委譲してください。" "$iter" "$eval_exit" "$eval_label"
else
  mark_state_after_step "$iter" "awaiting_claude_review" ""
  write_evidence "awaiting_claude_review" "Claudeが evidence と差分を見て、完了または次ステップを判断してください。" "$iter" "${eval_exit:-0}" "$eval_label"
fi

state_set loop_phase "awaiting_claude_review"
print_json_summary
