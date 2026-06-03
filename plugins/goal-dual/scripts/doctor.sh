#!/bin/bash
# goal-dual/scripts/doctor.sh — 導入状態と安全設定を診断する
# Usage: bash doctor.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/eval-registry.sh"

ok() { printf 'OK   %s\n' "$1"; }
warn() { printf 'WARN %s\n' "$1"; }
fail() { printf 'FAIL %s\n' "$1"; }

STATUS=0

echo "=== goal-dual doctor ==="
echo ""

if command -v jq >/dev/null 2>&1; then
  ok "jq is available"
else
  fail "jq is required"
  STATUS=1
fi

if command -v node >/dev/null 2>&1; then
  ok "node is available ($(node --version 2>/dev/null || echo unknown))"
else
  fail "Node.js 18+ is required"
  STATUS=1
fi

if command -v codex >/dev/null 2>&1; then
  ok "codex CLI is available"
else
  warn "codex CLI was not found; /goal-dual:run cannot delegate implementation"
fi

CODEX_ROOT="$(resolve_codex_plugin_root 2>/dev/null || true)"
if [ -n "$CODEX_ROOT" ] && [ -f "$CODEX_ROOT/scripts/codex-companion.mjs" ]; then
  ok "codex@openai-codex plugin found"
else
  warn "codex@openai-codex plugin not found"
fi

echo ""
echo "Repository:"
if command -v git >/dev/null 2>&1 && git rev-parse --git-dir >/dev/null 2>&1; then
  BRANCH="$(git branch --show-current 2>/dev/null || echo "")"
  [ -n "$BRANCH" ] && ok "git repository on branch ${BRANCH}" || warn "git repository is in detached HEAD"
  DIRTY="$(goal_dual_dirty_check || true)"
  if [ -n "$DIRTY" ]; then
    warn "working tree has changes outside .goal-dual/"
    printf '%s\n' "$DIRTY" | sed 's/^/     /'
  else
    ok "working tree is clean for goal-dual"
  fi
else
  warn "not a git repository; goal-dual will not have normal diff/commit protection"
fi

echo ""
echo "Safety defaults:"
SCOPE_MODE="${GOAL_DUAL_SCOPE_MODE:-enforce}"
WIP_COMMITS="${GOAL_DUAL_WIP_COMMITS:-0}"
FINAL_COMMIT="${GOAL_DUAL_FINAL_COMMIT:-0}"
HIGH_RISK="${GOAL_DUAL_ALLOW_HIGH_RISK:-0}"

[ "$SCOPE_MODE" = "enforce" ] && ok "scope violations stop by default" || warn "scope mode is ${SCOPE_MODE}; forbidden paths may not hard-stop"
[ "$WIP_COMMITS" = "1" ] && warn "WIP commits are enabled" || ok "WIP commits are off by default"
[ "$FINAL_COMMIT" = "1" ] && warn "final commit is enabled" || ok "final commit is off by default"
[ "$HIGH_RISK" = "1" ] && warn "high-risk Codex work is allowed to continue" || ok "high-risk Codex work stops for human review"

echo ""
echo "Eval command candidate:"
goal_dual_detect_eval_cmd
if [ -n "${EVAL_CMD:-}" ]; then
  if [ "$EVAL_CMD" = "make test" ]; then
    warn "make test candidate (${EVAL_CMD_SOURCE}); review Makefile before allowing automated eval"
  else
    ok "${EVAL_CMD} (${EVAL_CMD_SOURCE})"
  fi
else
  warn "no eval command detected; goal-dual will rely more on AI evaluation"
fi

echo ""
if [ "$STATUS" -eq 0 ]; then
  echo "doctor: ready enough to plan. Run /goal-dual:plan or /goal-dual:run when you are ready."
else
  echo "doctor: required dependencies are missing."
fi

exit "$STATUS"
