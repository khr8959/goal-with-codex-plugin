#!/bin/bash
# goal-dual/scripts/run-loop.sh — 中核イテレーションループの決定的ドライバ
# Usage: bash run-loop.sh
#
# 終了コード:
#   0  = ループ終了（state.completed=true を設定済み。run.md は 5. Finalize へ）
#   21 = final-checker サブエージェントが必要（loop_phase=await_final_check）
#   22 = code-reviewer サブエージェントが必要（loop_phase=await_code_review）
#   1  = エラー
#
# Claude オーケストレータ（run.md）は exit 21/22 を受けたら対応サブエージェントを
# 呼び、結果 JSON を書いてから本スクリプトを再呼び出しする。再呼び出し時は
# loop_phase を見て続きから再開し、iteration を二重に増分しない。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib.sh"

STATE=".goal-dual/state.json"
EVAL_DIR=".goal-dual/state/evaluations"

if [ ! -f "$STATE" ]; then
  echo "run-loop: $STATE が存在しません" >&2
  exit 1
fi

# --- 共有変数 ---
ITER=0
CODEX_VERDICT="incomplete"
FC_VERDICT="skip"
SKIP_EVAL=0

now_utc() { date -u +%Y-%m-%dT%H:%M:%SZ; }

incr_codex_failed() {
  local c
  c=$(state_get codex_failed_count)
  state_set codex_failed_count "$(( ${c:-0} + 1 ))"
}

mark_completed() {
  # $1 = stop_reason
  state_set completed true
  state_set stop_reason "$1"
  state_set loop_phase iterating
}

# --- verdict 合成（run.md の統合 verdict 表を機械化）---
synthesize_verdict() {
  # $1 = codex verdict, $2 = final_check verdict（skip の場合あり）
  local codex="$1" fc="$2"
  case "$codex" in
    complete)
      case "$fc" in
        complete)   echo "complete" ;;
        stop_human) echo "STOP_HUMAN" ;;
        *)          echo "incomplete" ;;  # incomplete / 想定外は安全側
      esac
      ;;
    regressed) echo "regressed" ;;
    *)         echo "incomplete" ;;  # incomplete / blocked / 想定外
  esac
}

write_synthesized() {
  # $1 = synthesized verdict
  local synth="$1"
  mkdir -p "$EVAL_DIR"
  local eval_exit codex_json fc_json next_action reason
  eval_exit=$(cat .goal-dual/state/eval-exit.txt 2>/dev/null || echo "")
  codex_json="$EVAL_DIR/codex-${ITER}.json"
  fc_json="$EVAL_DIR/final-check-${ITER}.json"
  # next_action: final-check の required_action を優先、なければ codex の next_action
  next_action=$(jq -r '.required_action // empty' "$fc_json" 2>/dev/null || true)
  if [ -z "$next_action" ]; then
    next_action=$(jq -r '.next_action // empty' "$codex_json" 2>/dev/null || true)
  fi
  reason=$(jq -r '.reason // empty' "$fc_json" 2>/dev/null || true)
  if [ -z "$reason" ]; then
    reason="codex=${CODEX_VERDICT} / final_check=${FC_VERDICT} を統合"
  fi
  jq -n \
    --argjson iteration "$ITER" \
    --arg verdict "$synth" \
    --arg eval_exit "${eval_exit:-}" \
    --arg codex_verdict "$CODEX_VERDICT" \
    --arg final_check_verdict "$FC_VERDICT" \
    --arg reason "$reason" \
    --arg next_action "$next_action" \
    '{
      iteration: $iteration,
      verdict: $verdict,
      eval_exit: ($eval_exit | tonumber? // null),
      codex_verdict: $codex_verdict,
      final_check_verdict: $final_check_verdict,
      reason: $reason,
      next_action: (if $next_action == "" then null else $next_action end)
    }' > "$EVAL_DIR/synthesized-${ITER}.json"
  state_set last_synthesized_verdict "$synth"
}

# --- front: 新規イテレーション先頭（dirty→increment→codex-work→[adv]→eval→evaluate）---
run_front() {
  local dirty_status=0
  bash "$SCRIPT_DIR/dirty-check.sh" >/dev/null 2>&1 || dirty_status=$?
  if [ "$dirty_status" -eq 1 ]; then
    goal_dual_progress "ループ停止: STOP_DIRTY（.goal-dual/ 外に未コミット変更）" <<EOF
iteration: $ITER
EOF
    mark_completed "STOP_DIRTY"
    exit 0
  fi

  ITER=$(jq -r '.iteration' "$STATE")
  ITER=$((ITER + 1))
  state_set iteration "$ITER"
  state_set last_updated_at "$(now_utc)"

  SKIP_EVAL=0
  CODEX_VERDICT="incomplete"
  FC_VERDICT="skip"

  local cw_status=0
  bash "$SCRIPT_DIR/codex-work.sh" .goal-dual || cw_status=$?
  local cw_result=".goal-dual/codex-work-result.json"
  local cw_st="" cw_risk=""
  if [ -f "$cw_result" ]; then
    cw_st=$(jq -r '.status // ""' "$cw_result" 2>/dev/null || echo "")
    cw_risk=$(jq -r '.risk // ""' "$cw_result" 2>/dev/null || echo "")
  fi

  if [ "$cw_status" -ne 0 ]; then
    incr_codex_failed
    SKIP_EVAL=1
    goal_dual_progress "Codex Work 失敗（exit ${cw_status}）→ eval スキップ" <<EOF
iteration: $ITER
EOF
  elif [ "$cw_st" = "blocked" ]; then
    SKIP_EVAL=1
    goal_dual_progress "Codex Work status=blocked → eval スキップ（safety が STOP_HUMAN 判定）" <<EOF
iteration: $ITER
EOF
  else
    if [ "$cw_st" = "implemented" ]; then
      state_set codex_failed_count 0
      local review_level
      review_level="${GOAL_DUAL_REVIEW_LEVEL:-$(state_get review_level)}"
      if [ "$review_level" = "strict" ] || [ "$cw_risk" = "high" ]; then
        local adv_status=0
        bash "$SCRIPT_DIR/adversarial-review.sh" >/dev/null 2>&1 || adv_status=$?
        if [ "$adv_status" -ne 0 ]; then
          incr_codex_failed
          SKIP_EVAL=1
          goal_dual_progress "批判的レビュー codex_failed（exit ${adv_status}）→ eval スキップ" <<EOF
iteration: $ITER
EOF
        fi
      fi
    fi
    # no_change はここを通り eval で状態確認する
  fi

  # scope_deny の enforce チェック（advisory では no-op）。
  # codex-work が fail/blocked でも working tree に変更があれば検知できるよう eval 前に実行。
  local sc_status=0
  bash "$SCRIPT_DIR/scope-check.sh" "$ITER" >/dev/null 2>&1 || sc_status=$?
  if [ "$sc_status" -eq 2 ]; then
    goal_dual_progress "ループ停止: STOP_SCOPE（scope_deny 違反を enforce で検知）" <<EOF
iteration: $ITER
EOF
    mark_completed "STOP_SCOPE"
    exit 0
  fi

  if [ "$SKIP_EVAL" -eq 0 ]; then
    bash "$SCRIPT_DIR/run-eval.sh" "$ITER" || true
    bash "$SCRIPT_DIR/codex-evaluate.sh" || true
    if [ -f ".goal-dual/CLAUDE_FINAL_CHECK_NEEDED" ]; then
      state_set loop_phase await_final_check
      goal_dual_progress "final-checker 要求 → exit 21" <<EOF
iteration: $ITER
EOF
      exit 21
    fi
    CODEX_VERDICT=$(jq -r '.verdict // "incomplete"' "$EVAL_DIR/codex-${ITER}.json" 2>/dev/null || echo "incomplete")
  fi
}

# --- tail: verdict 合成→safety→次アクション ---
# 戻り値: 0=ループ継続（次 front へ）。終端は exit する。
run_tail() {
  local synth
  synth=$(synthesize_verdict "$CODEX_VERDICT" "$FC_VERDICT")
  write_synthesized "$synth"

  if [ "$synth" = "STOP_HUMAN" ]; then
    goal_dual_progress "ループ停止: STOP_HUMAN（final-check=stop_human）" <<EOF
iteration: $ITER
EOF
    mark_completed "STOP_HUMAN"
    exit 0
  fi

  local s_status=0
  bash "$SCRIPT_DIR/safety.sh" "$ITER" || s_status=$?
  if [ "$s_status" -eq 10 ]; then
    mark_completed "STOP_STAGNANT"
    exit 0
  elif [ "$s_status" -eq 11 ]; then
    mark_completed "STOP_HUMAN"
    exit 0
  fi

  case "$synth" in
    complete)
      local tbe ci tc
      tbe=$(state_get task_breakdown_enabled)
      ci=$(state_get current_task_index); ci="${ci:-1}"
      tc=$(state_get task_count); tc="${tc:-1}"
      if [ "$tbe" = "true" ] && [ "$ci" -lt "$tc" ]; then
        state_set current_task_index "$(( ci + 1 ))"
        bash "$SCRIPT_DIR/commit-iter.sh" "$ITER" wip || true
        goal_dual_progress "小タスク完了 → 次タスク $(( ci + 1 ))/${tc}" <<EOF
iteration: $ITER
EOF
        return 0
      fi
      state_set loop_phase await_code_review
      goal_dual_progress "code-reviewer 要求 → exit 22" <<EOF
iteration: $ITER
EOF
      exit 22
      ;;
    regressed)
      goal_dual_progress "ループ停止: STOP_HUMAN（regressed）" <<EOF
iteration: $ITER
EOF
      mark_completed "STOP_HUMAN"
      exit 0
      ;;
    *)
      bash "$SCRIPT_DIR/commit-iter.sh" "$ITER" wip || true
      goal_dual_progress "incomplete → 次イテレーションへ" <<EOF
iteration: $ITER
next_action: $(jq -r '.next_action // "（なし）"' "$EVAL_DIR/synthesized-${ITER}.json" 2>/dev/null || echo "（なし）")
EOF
      return 0
      ;;
  esac
}

# --- resume: final-checker サブエージェント実行後 ---
resume_final_check() {
  ITER=$(jq -r '.iteration' "$STATE")
  local fc_file="$EVAL_DIR/final-check-${ITER}.json"
  if [ ! -f "$fc_file" ]; then
    state_set loop_phase await_final_check
    exit 21
  fi
  CODEX_VERDICT=$(jq -r '.verdict // "incomplete"' "$EVAL_DIR/codex-${ITER}.json" 2>/dev/null || echo "incomplete")
  FC_VERDICT=$(jq -r '.verdict // "incomplete"' "$fc_file" 2>/dev/null || echo "incomplete")
  state_set loop_phase iterating
  run_tail
}

# --- resume: code-reviewer サブエージェント実行後 ---
resume_code_review() {
  ITER=$(jq -r '.iteration' "$STATE")
  local cr_file="$EVAL_DIR/code-review-${ITER}.json"
  if [ ! -f "$cr_file" ]; then
    state_set loop_phase await_code_review
    exit 22
  fi
  local v
  v=$(jq -r '.verdict // "stop_human"' "$cr_file" 2>/dev/null || echo "stop_human")
  state_set loop_phase iterating
  if [ "$v" = "pass" ]; then
    bash "$SCRIPT_DIR/commit-iter.sh" "$ITER" pass || true
    goal_dual_progress "code-review pass → COMPLETE" <<EOF
iteration: $ITER
EOF
    mark_completed "COMPLETE"
    exit 0
  fi
  goal_dual_progress "code-review stop_human → STOP_HUMAN" <<EOF
iteration: $ITER
EOF
  mark_completed "STOP_HUMAN"
  exit 0
}

# === メイン ===
if [ "$(state_get completed)" = "true" ]; then
  exit 0
fi

PHASE=$(state_get loop_phase)
PHASE="${PHASE:-iterating}"

# resume ハンドラ（終端は exit、継続時は while へ合流して次 front を回す）
case "$PHASE" in
  await_final_check) resume_final_check ;;
  await_code_review) resume_code_review ;;
esac

while true; do
  run_front
  run_tail
done
