#!/bin/bash
# goal-dual/scripts/codex-evaluate.sh
# Codex にゴール達成判定させ evaluations/codex-N.json を保存する
# exit 0: 成功（JSON 保存済み） / exit 1: 失敗（codex_failed 相当）
set -euo pipefail

SCRIPTS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPTS/lib.sh"

CODEX_PLUGIN_ROOT=$(resolve_codex_plugin_root) || exit 1

INPUTS_FILE=$(mktemp)
bash "$SCRIPTS/collect-eval-inputs.sh" > "$INPUTS_FILE"
# shellcheck disable=SC1090
source "$INPUTS_FILE"
rm -f "$INPUTS_FILE"

ITER=$(jq -r '.iteration' .goal-dual/state.json)
LOG_FILE=".goal-dual/logs/codex-eval-${ITER}-$(date +%Y%m%d-%H%M%S).log"
mkdir -p .goal-dual/logs

OUTPUT=$(node "$CODEX_PLUGIN_ROOT/scripts/codex-companion.mjs" task \
"ゴール達成判定を行え。以下の情報を読み、厳密に JSON のみを出力せよ（前後にテキスト不可）。

【ゴール定義】
${GOAL}

【完了条件（最優先で確認すること）】
${ACCEPTANCE_CRITERIA}

【現在の小タスク（タスク分割が有効な場合のみ参照）】
${CURRENT_TASK:-（タスク分割なし）}

【eval-cmd 結果】
exit code: ${EVAL_EXIT}
ログ抜粋:
${EVAL_LOG}

【変更統計】
${DIFF_STAT}

【変更ファイル一覧】
${DIFF_FILES}

【出力形式（この JSON のみを返せ）】
{
  \"verdict\": \"complete\" または \"incomplete\" または \"regressed\",
  \"confidence\": 0.0-1.0,
  \"evidence\": [\"根拠1\", \"根拠2\"],
  \"missing\": [\"未対応項目1\"],
  \"next_action\": \"次イテレーションの方針\" または null
}

【判定ルール】
- eval_exit が 0 でない場合は必ず incomplete
- 完了条件が設定されている場合、各項目を確認することを最優先とする
- 完了条件をすべて満たしていない場合は incomplete（eval_exit=0 でも）
- confidence は根拠の強さを 0.0-1.0 で表す（complete の場合は 0.6 以上推奨）" \
</dev/null 2>&1) || true

echo "$OUTPUT" > "$LOG_FILE"

JSON=$(echo "$OUTPUT" | extract_codex_json)
EVAL_DIR=".goal-dual/state/evaluations"
mkdir -p "$EVAL_DIR"

if echo "$JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); assert 'verdict' in d" 2>/dev/null; then
  printf '%s\n' "$JSON" > "${EVAL_DIR}/codex-${ITER}.json"
else
  printf '%s\n' '{"verdict":"incomplete","confidence":0.0,"evidence":["codex_failed"],"missing":["Codex の評価に失敗"],"next_action":"Codex を再試行するか Claude 評価のみで判断"}' \
    > "${EVAL_DIR}/codex-${ITER}.json"
  exit 1
fi
