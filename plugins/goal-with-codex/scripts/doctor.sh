#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/eval-registry.sh"

failures=0

check() {
  local label="$1"
  shift
  if "$@"; then
    echo "OK   $label"
  else
    echo "FAIL $label"
    failures=$((failures + 1))
  fi
}

check "git repository" sh -c "git rev-parse --show-toplevel >/dev/null 2>&1"
check "jq available" sh -c "command -v jq >/dev/null 2>&1"
check "node available" sh -c "command -v node >/dev/null 2>&1"
if codex_root=$(gwc_require_codex_plugin_root 2>/dev/null); then
  echo "OK   codex@openai-codex plugin: $codex_root"
else
  echo "FAIL codex@openai-codex plugin"
  failures=$((failures + 1))
fi

gwc_detect_eval_cmd
if [ -n "$EVAL_CMD" ]; then
  echo "OK   eval command detected: $EVAL_CMD ($EVAL_CMD_SOURCE)"
else
  echo "WARN no eval command detected"
fi

dirty=$(gwc_dirty_check)
if [ -z "$dirty" ]; then
  echo "OK   working tree clean for a new goal"
else
  echo "WARN existing changes outside .goal-with-codex:"
  echo "$dirty"
fi

if [ "$failures" -gt 0 ]; then
  exit 1
fi
