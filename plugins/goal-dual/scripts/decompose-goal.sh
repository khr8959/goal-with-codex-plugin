#!/bin/bash
# goal-dual/scripts/decompose-goal.sh
# ゴールを 2〜6 個の小タスクに分割し task-breakdown.md を生成する
# 小さなゴールでは分割せず「単一タスク」として扱う
# exit 0: 成功（分割あり or 単一タスク判定）/ exit 1: Codex 失敗
set -euo pipefail

SCRIPTS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPTS/lib.sh"

OUTPUT_FILE=".goal-dual/state/task-breakdown.md"
mkdir -p "$(dirname "$OUTPUT_FILE")"

# 再開時はスキップ
if [ -f "$OUTPUT_FILE" ]; then
  echo "task-breakdown.md は既存（再開）: スキップ"
  exit 0
fi

CODEX_PLUGIN_ROOT=$(resolve_codex_plugin_root) || exit 1
GOAL=$(cat .goal-dual/goal.md 2>/dev/null || echo "")
ACCEPTANCE=$(cat .goal-dual/state/acceptance-criteria.md 2>/dev/null || echo "")

OUTPUT=$(node "$CODEX_PLUGIN_ROOT/scripts/codex-companion.mjs" task \
"以下のゴールが「大きいゴール」か「小さいゴール」かを判断し、大きい場合は 2〜6 個の小タスクに分割せよ。

【判断基準】
- 複数の独立した機能追加・画面作成・ステップが含まれる → 大きいゴール（分割する）
- 単一の修正・1 ファイル程度の変更・タイポ修正 → 小さいゴール（分割しない）

【出力フォーマット（どちらか一方のみ出力）】

分割する場合:
task_count: <数値>
1. <小タスク1の説明（1行）>
2. <小タスク2の説明（1行）>
...

分割しない場合:
task_count: 1
1. <ゴール全体をそのまま 1 タスクとして記載>

【ゴール】
${GOAL}

【完了条件】
${ACCEPTANCE}" \
</dev/null 2>&1) || true

# task_count を抽出
TASK_COUNT=$(echo "$OUTPUT" | grep -oE '^task_count: [0-9]+' | grep -oE '[0-9]+' | head -1 || echo "")

if [ -z "$TASK_COUNT" ] || [ "$TASK_COUNT" -lt 1 ] 2>/dev/null; then
  # Codex 失敗: 単一タスクとして扱う
  TASK_COUNT=1
  {
    printf '## タスク一覧\n\n'
    printf 'task_count: 1\n\n'
    printf '1. ゴール全体を 1 タスクとして実装する\n'
  } > "$OUTPUT_FILE"
  echo "task-breakdown.md をデフォルト（単一タスク）で生成しました"
  exit 0
fi

{
  printf '## タスク一覧\n\n'
  echo "$OUTPUT"
} > "$OUTPUT_FILE"

# state.json にタスク追跡情報を保存
jq \
  --argjson count "$TASK_COUNT" \
  '.task_breakdown_enabled = true | .current_task_index = 1 | .task_count = $count' \
  .goal-dual/state.json > /tmp/state_tmp.json \
  && mv /tmp/state_tmp.json .goal-dual/state.json

if [ "$TASK_COUNT" -gt 1 ]; then
  echo "task-breakdown.md を生成しました（${TASK_COUNT} タスク）"
else
  echo "task-breakdown.md を生成しました（単一タスク）"
fi
