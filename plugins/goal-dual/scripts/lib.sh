#!/bin/bash
# goal-dual/scripts/lib.sh — 共通ユーティリティ（source で読み込む）

# codex exec の出力からヘッダ・推論ログを除いて最後のJSON objectを抽出する
extract_codex_json() {
  python3 -c '
import sys, json
t = sys.stdin.read()
last = None
i = 0
while i < len(t):
    if t[i] == "{":
        depth = 0
        for j in range(i, len(t)):
            if t[j] == "{":
                depth += 1
            elif t[j] == "}":
                depth -= 1
                if depth == 0:
                    snippet = t[i:j+1]
                    try:
                        json.loads(snippet)
                        last = snippet
                    except json.JSONDecodeError:
                        pass
                    i = j
                    break
    i += 1
sys.stdout.write(last if last else t.strip())
'
}

# .goal-dual/ と .goal-dual-archive/ を除外した dirty check
goal_dual_dirty_check() {
  git status --porcelain | grep -v -E \
    '^\?\? \.goal-dual/$|^\?\? \.goal-dual/.*|^.. \.goal-dual/.*|^\?\? \.goal-dual-archive/$|^\?\? \.goal-dual-archive/.*|^.. \.goal-dual-archive/.*' \
    || true
}

# state.json の特定キーを更新（atomic）
state_set() {
  local key="$1"
  local value="$2"
  local tmp
  tmp=$(mktemp)
  # 値が JSON リテラル（数値・bool・null・配列・オブジェクト）か文字列かを判定
  if echo "$value" | python3 -c "import sys,json; json.loads(sys.stdin.read())" 2>/dev/null; then
    jq --arg k "$key" --argjson v "$value" '.[$k] = $v' .goal-dual/state.json > "$tmp"
  else
    jq --arg k "$key" --arg v "$value" '.[$k] = $v' .goal-dual/state.json > "$tmp"
  fi
  mv "$tmp" .goal-dual/state.json
}

# state.json から値を取得
state_get() {
  local key="$1"
  jq -r ".$key // empty" .goal-dual/state.json 2>/dev/null
}

# progress.txt に goal-dual 用セクションを追記（.goal-dual/ 内の progress.txt を対象）
goal_dual_progress() {
  local heading="$1"
  {
    echo ""
    echo "## [$(date)] - ${heading}"
    cat
    echo "---"
  } >> .goal-dual/progress.txt
}

# codex@openai-codex プラグインの root を返す（優先順位: CLAUDE_PLUGIN_ROOT → state.json → 動的解決）
resolve_codex_plugin_root() {
  # Claude Code が注入する CLAUDE_PLUGIN_ROOT を最優先で使う（codex-companion.mjs の存在確認）
  if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "$CLAUDE_PLUGIN_ROOT/scripts/codex-companion.mjs" ]; then
    echo "$CLAUDE_PLUGIN_ROOT"
    return
  fi
  if [ -f .goal-dual/state.json ]; then
    local from_state
    from_state=$(jq -r '.codex_plugin_root // .plugin_root // empty' .goal-dual/state.json 2>/dev/null)
    if [ -n "$from_state" ] && [ -f "$from_state/scripts/codex-companion.mjs" ]; then
      echo "$from_state"
      return
    fi
  fi
  ls -d "$HOME/.claude/plugins/cache/openai-codex/codex/"*/ 2>/dev/null \
    | sort -V | tail -1 | sed 's|/$||'
}

# goal-dual プラグイン自身の root を返す（優先順位: state.json → BASH_SOURCE から逆算）
resolve_goal_dual_plugin_root() {
  if [ -f .goal-dual/state.json ]; then
    local from_state
    from_state=$(jq -r '.goal_dual_plugin_root // empty' .goal-dual/state.json 2>/dev/null)
    if [ -n "$from_state" ] && [ -d "$from_state/scripts" ]; then
      echo "$from_state"
      return
    fi
  fi
  # lib.sh は goal-dual/scripts/ にある → 一つ上が plugin root
  local scripts_dir
  scripts_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  dirname "$scripts_dir"
}

# 後方互換 shim（codex plugin root を返す）
resolve_plugin_root() {
  resolve_codex_plugin_root
}

# 直近から同じ synthesized verdict が連続している数を返す（最大 threshold）
consecutive_same_verdict_count() {
  local threshold="${GOAL_DUAL_STAGNATION_THRESHOLD:-3}"
  local synth_dir=".goal-dual/state/evaluations"
  if [ ! -d "$synth_dir" ]; then
    echo "0"
    return
  fi

  local files
  files=$(find "$synth_dir" -name "synthesized-*.json" 2>/dev/null \
    | sed -E 's/.*synthesized-([0-9]+)\.json$/\1 &/' \
    | sort -rn \
    | awk '{print $2}' \
    | head -"$threshold")
  if [ -z "$files" ]; then
    echo "0"
    return
  fi

  local first_verdict=""
  local count=0
  local file
  while IFS= read -r file; do
    [ -n "$file" ] || continue
    local verdict
    verdict=$(jq -r '.verdict // "incomplete"' "$file" 2>/dev/null || echo "incomplete")
    if [ -z "$first_verdict" ]; then
      first_verdict="$verdict"
      count=1
      continue
    fi
    if [ "$verdict" = "$first_verdict" ]; then
      count=$(( count + 1 ))
    else
      break
    fi
  done <<EOF
$files
EOF

  if [ "$count" -gt "$threshold" ]; then
    echo "$threshold"
  else
    echo "$count"
  fi
}
