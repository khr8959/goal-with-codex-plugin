#!/bin/bash
# goal-dual/scripts/codex-work.sh
# Codex Worker に調査・計画・実装・自己レビューを1回のループで実施させ、
# 結果を .goal-dual/codex-work-result.json に保存する。
#
# Codex Work は調査・計画・実装・自己レビューを統合した現在の実装経路。
#
# 使用方法: codex-work.sh <goal-dual-dir>
#   goal-dual-dir: .goal-dual/ のパス（通常は ".goal-dual"）
#
# exit 0: 成功（.goal-dual/codex-work-result.json に JSON を保存済み）
# exit 1: 失敗
set -euo pipefail

SCRIPTS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPTS/lib.sh"

# 引数チェック
GOAL_DUAL_DIR="${1:-.goal-dual}"
if [ ! -d "$GOAL_DUAL_DIR" ]; then
  mkdir -p "$GOAL_DUAL_DIR"
fi

CODEX_PLUGIN_ROOT=$(resolve_codex_plugin_root) || exit 1
ITER=$(jq -r '.iteration' "$GOAL_DUAL_DIR/state.json" 2>/dev/null || echo "0")
LOG_FILE="$GOAL_DUAL_DIR/logs/codex-work-${ITER}-$(date +%Y%m%d-%H%M%S).log"
mkdir -p "$GOAL_DUAL_DIR/logs"

# --- コンテキストの収集 ---

# ゴール文
GOAL=""
if [ -f "$GOAL_DUAL_DIR/goal.txt" ]; then
  GOAL=$(cat "$GOAL_DUAL_DIR/goal.txt")
elif [ -f "$GOAL_DUAL_DIR/goal.md" ]; then
  GOAL=$(cat "$GOAL_DUAL_DIR/goal.md")
fi

# 完了条件
COMPLETION_CRITERIA=""
if [ -f "$GOAL_DUAL_DIR/completion-criteria.md" ]; then
  COMPLETION_CRITERIA=$(cat "$GOAL_DUAL_DIR/completion-criteria.md")
elif [ -f "$GOAL_DUAL_DIR/state/acceptance-criteria.md" ]; then
  COMPLETION_CRITERIA=$(cat "$GOAL_DUAL_DIR/state/acceptance-criteria.md")
fi

# 変更禁止パス（scope.md から抽出）
FORBIDDEN_PATHS=""
if [ -f "$GOAL_DUAL_DIR/state/scope.md" ]; then
  FORBIDDEN_PATHS=$(awk '/### 変更してはいけない場所/{f=1;next} /^###/{f=0} f && /^-/' \
    "$GOAL_DUAL_DIR/state/scope.md" | sed 's/^- //' | grep -v "特に制限なし" || true)
fi

# goal-dual-plan の内容
PLAN_CONTEXT=""
if [ -f "$GOAL_DUAL_DIR/plan/plan.md" ]; then
  PLAN_CONTEXT=$(cat "$GOAL_DUAL_DIR/plan/plan.md")
fi

ALLOWED_TEST_CHANGES=""
if [ -f "$GOAL_DUAL_DIR/plan/status.json" ]; then
  ALLOWED_TEST_CHANGES=$(jq -r '
    (.allowed_test_changes // [])
    | if length == 0 then "" else map(
        if type == "object" then
          "- " + ((.file // "対象未指定")|tostring) + ": " + ((.reason // "理由未指定")|tostring)
        else
          "- " + tostring
        end
      ) | join("\n") end
  ' "$GOAL_DUAL_DIR/plan/status.json" 2>/dev/null || true)
fi

# 前回の評価サマリー
PREV_EVAL_SUMMARY=""
if [ -f "$GOAL_DUAL_DIR/prev-eval-summary.txt" ]; then
  PREV_EVAL_SUMMARY=$(cat "$GOAL_DUAL_DIR/prev-eval-summary.txt")
else
  PREV_ITER=$((ITER - 1))
  if [ "$PREV_ITER" -gt 0 ] && [ -f "$GOAL_DUAL_DIR/state/evaluations/synthesized-${PREV_ITER}.json" ]; then
    PREV_EVAL_SUMMARY=$(cat "$GOAL_DUAL_DIR/state/evaluations/synthesized-${PREV_ITER}.json")
  fi
fi

# 前回のテスト失敗内容
PREV_TEST_FAILURE=""
PREV_ITER=$((ITER - 1))
if [ "$PREV_ITER" -gt 0 ] && [ -d "$GOAL_DUAL_DIR/logs" ]; then
  PREV_EVAL_LOG=$(ls "$GOAL_DUAL_DIR/logs/eval-cmd-${PREV_ITER}-"*.log 2>/dev/null | sort | tail -1 || true)
  if [ -n "$PREV_EVAL_LOG" ] && [ -f "$PREV_EVAL_LOG" ]; then
    PREV_TEST_FAILURE=$(tail -50 "$PREV_EVAL_LOG")
  fi
fi

# --- Codex Worker への問い合わせ ---

CONTEXT_SECTION=""
[ -n "$GOAL" ] && CONTEXT_SECTION="${CONTEXT_SECTION}
【ゴール】
${GOAL}"

[ -n "$COMPLETION_CRITERIA" ] && CONTEXT_SECTION="${CONTEXT_SECTION}

【完了条件（最優先で参照すること）】
${COMPLETION_CRITERIA}"

[ -n "$FORBIDDEN_PATHS" ] && CONTEXT_SECTION="${CONTEXT_SECTION}

【変更禁止パス（絶対に触らないこと）】
${FORBIDDEN_PATHS}"

[ -n "$PLAN_CONTEXT" ] && CONTEXT_SECTION="${CONTEXT_SECTION}

【事前 plan（ユーザー確認済みの実装方針として扱うこと）】
${PLAN_CONTEXT}"

if [ -n "$ALLOWED_TEST_CHANGES" ]; then
  CONTEXT_SECTION="${CONTEXT_SECTION}

【許可済みの既存テスト期待値変更】
${ALLOWED_TEST_CHANGES}"
else
  CONTEXT_SECTION="${CONTEXT_SECTION}

【許可済みの既存テスト期待値変更】
なし"
fi

[ -n "$PREV_EVAL_SUMMARY" ] && CONTEXT_SECTION="${CONTEXT_SECTION}

【前回の評価サマリー（優先して参照すること）】
${PREV_EVAL_SUMMARY}"

[ -n "$PREV_TEST_FAILURE" ] && CONTEXT_SECTION="${CONTEXT_SECTION}

【前回のテスト失敗内容（優先して修正すること）】
${PREV_TEST_FAILURE}"

OUTPUT=$(node "$CODEX_PLUGIN_ROOT/scripts/codex-companion.mjs" task --write \
"以下のコンテキストに基づき、1回のループで調査・計画・実装・自己レビューを実施せよ。
結果は必ず以下の JSON 形式のみで出力すること（コードブロック不要、前後にテキスト不可）。

【CONTEXT】
${CONTEXT_SECTION}

【実装ルール】
- 1ループでは小さく直す（大きすぎる変更は blocked を返して次ループに持ち越す）
- 完了条件を常に参照する
- 前回の評価結果とテスト失敗を優先して直す
- 変更禁止パスには触らない
- 既存テストは現在の仕様の証拠として扱い、原則として期待値を変更しない
- 既存テスト期待値を変更してよいのは「許可済みの既存テスト期待値変更」に明記されている場合のみ
- ゴール・完了条件・事前 plan と既存テスト期待値が矛盾し、許可済み変更にない場合は、テストを変更せず blocked を返す
- 新仕様を守るための追加テストは作成してよい
- 迷ったら blocked を返す
- no_change は「変更が不要と判断した」または「変更できるものが見つからない」場合

【手順】
1. 調査: 関連ファイル・既存実装・テスト構造を調べる
2. 計画: 今回のループで実施する修正方針を決める（小さく絞る）
3. 実装: コードを変更する（TypeScript の any 禁止、console.log 禁止）
4. 自己レビュー: 変更内容・リスク・次に見るべき点をまとめる

【出力形式（この JSON のみを返せ）】
{
  \"status\": \"implemented\" または \"blocked\" または \"no_change\",
  \"changed_files\": [\"変更したファイルのパス\"],
  \"summary\": \"実装内容の短い説明（日本語）\",
  \"self_review\": \"自分で確認した内容（日本語）\",
  \"risk\": \"low\" または \"medium\" または \"high\",
  \"next_action\": \"次に確認すべきこと（日本語）\"
}" \
</dev/null 2>&1) || true

echo "$OUTPUT" > "$LOG_FILE"

# JSON を抽出して検証
JSON=$(echo "$OUTPUT" | extract_codex_json)

RESULT_FILE="$GOAL_DUAL_DIR/codex-work-result.json"

if echo "$JSON" | python3 -c "
import sys, json
d = json.load(sys.stdin)
assert 'status' in d
assert d['status'] in ('implemented', 'blocked', 'no_change')
assert 'changed_files' in d
assert 'summary' in d
assert 'self_review' in d
assert 'risk' in d
assert 'next_action' in d
" 2>/dev/null; then
  printf '%s\n' "$JSON" > "$RESULT_FILE"
else
  # JSON 抽出・検証失敗時はエラー JSON を保存して exit 1
  printf '%s\n' \
    '{"status":"blocked","changed_files":[],"summary":"Codex Worker の出力解析に失敗した","self_review":"JSON 形式が不正またはレスポンスが空","risk":"high","next_action":"codex-work.sh のログを確認すること"}' \
    > "$RESULT_FILE"
  exit 1
fi

# ログ: status / risk / changed_files を抽出して記録
STATUS=$(jq -r '.status' "$RESULT_FILE")
RISK=$(jq -r '.risk' "$RESULT_FILE")
CHANGED_FILES=$(jq -r '.changed_files | join(" ")' "$RESULT_FILE")

{
  echo ""
  echo "## [$(date)] - Codex Work iter=${ITER}"
  echo "status: ${STATUS}"
  echo "risk: ${RISK}"
  echo "changed_files: ${CHANGED_FILES:-（なし）}"
  echo "summary: $(jq -r '.summary' "$RESULT_FILE")"
  echo "next_action: $(jq -r '.next_action' "$RESULT_FILE")"
  echo "---"
} >> "$GOAL_DUAL_DIR/progress.txt" 2>/dev/null || true

echo "$JSON"
