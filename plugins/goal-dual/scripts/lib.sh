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

# .goal-dual/ 配下を除外した dirty check
goal_dual_dirty_check() {
  git status --porcelain | grep -v -E \
    '^\?\? \.goal-dual/$|^\?\? \.goal-dual/.*|^.. \.goal-dual/.*' \
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

# PLUGIN_ROOT を返す（優先順位: 環境変数 → state.json → 動的解決）
resolve_plugin_root() {
  if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ]; then
    echo "$CLAUDE_PLUGIN_ROOT"
    return
  fi
  # state.json に保存された plugin_root をフォールバックとして利用
  if [ -f .goal-dual/state.json ]; then
    local from_state
    from_state=$(jq -r '.plugin_root // empty' .goal-dual/state.json 2>/dev/null)
    if [ -n "$from_state" ] && [ -f "$from_state/scripts/codex-companion.mjs" ]; then
      echo "$from_state"
      return
    fi
  fi
  ls -d "$HOME/.claude/plugins/cache/openai-codex/codex/"*/ 2>/dev/null \
    | sort -V | tail -1 | sed 's|/$||'
}

# 直近 N 件の synthesized verdict が同一かを判定し、同一なら N、そうでなければ
# 直近に連続する同一 verdict 数を返す（safety.sh 方式: unique 数チェック）
consecutive_same_verdict_count() {
  local threshold="${GOAL_DUAL_STAGNATION_THRESHOLD:-3}"
  local synth_dir=".goal-dual/state/evaluations"
  local synth_count
  synth_count=$(find "$synth_dir" -name "synthesized-*.json" 2>/dev/null | wc -l | tr -d ' ')
  if [ "${synth_count:-0}" -lt "$threshold" ]; then
    echo "0"
    return
  fi
  # 直近 N 件の verdict を取得し、unique 数を数える
  local uniq_count
  uniq_count=$(ls -t "$synth_dir"/synthesized-*.json 2>/dev/null \
    | head -"$threshold" \
    | xargs -I{} jq -r '.verdict // "incomplete"' {} 2>/dev/null \
    | sort -u | wc -l | tr -d ' ')
  if [ "${uniq_count:-0}" -eq 1 ]; then
    echo "$threshold"
  else
    echo "0"
  fi
}
