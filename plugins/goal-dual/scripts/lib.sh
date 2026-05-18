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

# PLUGIN_ROOT を返す（環境変数未設定時は動的解決）
resolve_plugin_root() {
  if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ]; then
    echo "$CLAUDE_PLUGIN_ROOT"
    return
  fi
  ls -d "$HOME/.claude/plugins/cache/openai-codex/codex/"*/ 2>/dev/null \
    | sort -V | tail -1 | sed 's|/$||'
}

# synthesized-N.json を読んで連続同一 verdict のカウントを返す
consecutive_same_verdict_count() {
  local threshold="${GOAL_DUAL_STAGNATION_THRESHOLD:-3}"
  local count=0
  local last_verdict=""
  # 新しい順にソート
  for f in $(ls -t .goal-dual/state/evaluations/synthesized-*.json 2>/dev/null | head -"$threshold"); do
    local v
    v=$(jq -r '.verdict // "incomplete"' "$f" 2>/dev/null)
    if [ -z "$last_verdict" ]; then
      last_verdict="$v"
      count=1
    elif [ "$v" = "$last_verdict" ]; then
      count=$((count + 1))
    else
      break
    fi
  done
  echo "$count"
}
