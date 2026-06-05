#!/bin/bash
# goal-with-codex shared helpers

GWC_DIR="${GOAL_WITH_CODEX_DIR:-.goal-with-codex}"
GWC_STATE="$GWC_DIR/state.json"

gwc_now_utc() { date -u +%Y-%m-%dT%H:%M:%SZ; }

gwc_state_set() {
  local key="$1"
  local value="$2"
  local tmp
  tmp=$(mktemp)
  if echo "$value" | python3 -c "import sys,json; json.loads(sys.stdin.read())" 2>/dev/null; then
    jq --arg k "$key" --argjson v "$value" '.[$k] = $v' "$GWC_STATE" > "$tmp"
  else
    jq --arg k "$key" --arg v "$value" '.[$k] = $v' "$GWC_STATE" > "$tmp"
  fi
  mv "$tmp" "$GWC_STATE"
}

gwc_state_get() {
  local key="$1"
  jq -r ".$key // empty" "$GWC_STATE" 2>/dev/null
}

gwc_dirty_check() {
  git status --porcelain 2>/dev/null | grep -v -E \
    '^\?\? \.goal-with-codex/$|^\?\? \.goal-with-codex/.*|^.. \.goal-with-codex/.*' \
    || true
}

gwc_progress() {
  local heading="$1"
  mkdir -p "$GWC_DIR"
  {
    echo ""
    echo "## [$(date)] - ${heading}"
    cat
    echo "---"
  } >> "$GWC_DIR/progress.md"
}

gwc_event() {
  local type="$1"
  local payload="${2:-{}}"
  mkdir -p "$GWC_DIR/state"
  if ! echo "$payload" | jq empty >/dev/null 2>&1; then
    payload="{}"
  fi
  jq -nc \
    --arg type "$type" \
    --arg time "$(gwc_now_utc)" \
    --argjson payload "$payload" \
    '{time:$time,type:$type} + $payload' >> "$GWC_DIR/events.jsonl" 2>/dev/null || true
}

gwc_redact_for_llm() {
  sed -E \
    -e 's/(sk-[A-Za-z0-9_-]{16,})/[REDACTED_OPENAI_KEY]/g' \
    -e 's/(gh[pousr]_[A-Za-z0-9_]{16,})/[REDACTED_GITHUB_TOKEN]/g' \
    -e 's/(AKIA[0-9A-Z]{16})/[REDACTED_AWS_ACCESS_KEY]/g' \
    -e 's/(AIza[0-9A-Za-z_-]{20,})/[REDACTED_GOOGLE_API_KEY]/g' \
    -e 's/(xox[baprs]-[A-Za-z0-9-]{10,})/[REDACTED_SLACK_TOKEN]/g' \
    -e 's/([A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]{20,})/[REDACTED_JWT]/g' \
    -e 's/((api[_-]?key|token|secret|password|passwd|pwd)[[:space:]]*[:=][[:space:]]*)[^[:space:]]+/\1[REDACTED]/Ig'
}

gwc_resolve_codex_plugin_root() {
  if [ -n "${CODEX_PLUGIN_ROOT:-}" ] && [ -f "$CODEX_PLUGIN_ROOT/scripts/codex-companion.mjs" ]; then
    echo "$CODEX_PLUGIN_ROOT"
    return
  fi
  if [ -f "$GWC_STATE" ]; then
    local from_state
    from_state=$(jq -r '.codex_plugin_root // empty' "$GWC_STATE" 2>/dev/null)
    if [ -n "$from_state" ] && [ -f "$from_state/scripts/codex-companion.mjs" ]; then
      echo "$from_state"
      return
    fi
  fi
  ls -d "$HOME/.claude/plugins/cache/openai-codex/codex/"*/ 2>/dev/null \
    | sort -V | tail -1 | sed 's|/$||'
}

gwc_require_codex_plugin_root() {
  local root
  root=$(gwc_resolve_codex_plugin_root)
  if [ -z "$root" ] || [ ! -f "$root/scripts/codex-companion.mjs" ]; then
    echo "codex@openai-codex plugin が見つかりません。Claude Code で /install codex@openai-codex を実行してください。" >&2
    return 1
  fi
  echo "$root"
}

gwc_changed_files_json() {
  git status --porcelain 2>/dev/null \
    | grep -v -E '^\?\? \.goal-with-codex/|^.. \.goal-with-codex/' \
    | sed 's/^...//' \
    | jq -R . \
    | jq -s 'unique' 2>/dev/null || echo "[]"
}

gwc_risk_level() {
  local goal="${1:-}"
  local changed_count="${2:-0}"
  local text
  text=$(printf '%s' "$goal" | tr '[:upper:]' '[:lower:]')
  if printf '%s' "$text" | grep -Eq 'auth|oauth|login|permission|billing|payment|stripe|delete|destructive|migration|database|db|security|secret|token|production|prod'; then
    echo "high"
  elif [ "${changed_count:-0}" -ge 6 ]; then
    echo "medium"
  else
    echo "low"
  fi
}
