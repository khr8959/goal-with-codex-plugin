#!/bin/bash
# goal-dual/scripts/codex-evaluate.sh
# Codex にゴール達成判定させ evaluations/codex-N.json を保存する
# exit 0: 成功（JSON 保存済み） / exit 1: 失敗（codex_failed 相当）
#
# 評価フロー軽量化ロジック:
#   - eval_exit != 0 の場合は AI 評価を省略して即 incomplete を出力し終了する
#   - eval_exit == 0 の場合は Codex evaluator のみ実行する
#   - Codex が complete を返した場合のみ .goal-dual/CLAUDE_FINAL_CHECK_NEEDED フラグを書き出す
#   - Codex が blocked または regressed を返した場合は .goal-dual/STOP_HUMAN_CANDIDATE フラグを書き出す
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
EVAL_CMD_VALUE=$(jq -r '.eval_cmd // ""' .goal-dual/state.json 2>/dev/null || echo "")
NO_EVAL_CMD=false
EVAL_CMD_CONFIDENCE_RULE=""
if [ -z "$EVAL_CMD_VALUE" ]; then
  NO_EVAL_CMD=true
  EVAL_CMD_CONFIDENCE_RULE="
- eval-cmd が設定されていないため、complete と判定する confidence は 0.8 以上を要求する
- eval-cmd が設定されていない場合、confidence が 0.8 未満なら verdict は incomplete にする"
fi
EVAL_DIR=".goal-dual/state/evaluations"
mkdir -p "$EVAL_DIR"
LOG_FILE=".goal-dual/logs/codex-eval-${ITER}-$(date +%Y%m%d-%H%M%S).log"
mkdir -p .goal-dual/logs

# eval_exit != 0 の場合は AI 評価を省略して即 incomplete を出力する
if [ "${EVAL_EXIT:-0}" != "0" ]; then
  echo "[codex-evaluate] eval_exit=${EVAL_EXIT} != 0: AI 評価を省略して incomplete を出力" >> "$LOG_FILE"
  printf '%s\n' "{\"verdict\":\"incomplete\",\"confidence\":0.0,\"evidence\":[\"eval_exit=${EVAL_EXIT}\"],\"missing\":[\"テストが失敗している（eval_exit=${EVAL_EXIT}）\"],\"next_action\":\"テスト失敗の原因を修正する\"}" \
    > "${EVAL_DIR}/codex-${ITER}.json"
  # フラグファイルを削除（前回の残滓を消す）
  rm -f .goal-dual/CLAUDE_FINAL_CHECK_NEEDED .goal-dual/STOP_HUMAN_CANDIDATE
  exit 0
fi

# eval_exit == 0 の場合のみ Codex evaluator を実行する
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
  \"verdict\": \"complete\" または \"incomplete\" または \"regressed\" または \"blocked\",
  \"confidence\": 0.0-1.0,
  \"evidence\": [\"根拠1\", \"根拠2\"],
  \"missing\": [\"未対応項目1\"],
  \"next_action\": \"次イテレーションの方針\" または null
}

【判定ルール】
- eval_exit が 0 でない場合は必ず incomplete
- 完了条件が設定されている場合、各項目を確認することを最優先とする
- 完了条件をすべて満たしていない場合は incomplete（eval_exit=0 でも）
- confidence は根拠の強さを 0.0-1.0 で表す（complete の場合は 0.6 以上推奨）
- eval-cmd が設定されている場合は従来通り complete の confidence は 0.6 以上推奨
${EVAL_CMD_CONFIDENCE_RULE}
- blocked: 何を修正すればよいか判断できない、または変更禁止範囲を触らないと進めない場合" \
</dev/null 2>&1) || true

echo "$OUTPUT" > "$LOG_FILE"

JSON=$(echo "$OUTPUT" | extract_codex_json)

if echo "$JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); assert 'verdict' in d" 2>/dev/null; then
  printf '%s\n' "$JSON" > "${EVAL_DIR}/codex-${ITER}.json"
else
  printf '%s\n' '{"verdict":"incomplete","confidence":0.0,"evidence":["codex_failed"],"missing":["Codex の評価に失敗"],"next_action":"Codex を再試行するか Claude 評価のみで判断"}' \
    > "${EVAL_DIR}/codex-${ITER}.json"
  exit 1
fi

if [ "$NO_EVAL_CMD" = "true" ] && jq -e '
  (.verdict // "incomplete") == "complete"
  and (((.confidence // 0) | try tonumber catch 0) < 0.8)
' "${EVAL_DIR}/codex-${ITER}.json" >/dev/null 2>&1; then
  TMP_EVAL=$(mktemp)
  jq '
    .verdict = "incomplete"
    | .missing = ((.missing // []) + ["eval-cmd がないため、confidence 0.8 未満の complete 判定を保守的に incomplete へ格下げした"])
    | .next_action = (((.next_action // "") | tostring) as $next
        | if $next == "" or $next == "null" then
            "eval-cmd がないため保守的に判定。自動テストを追加するか手動確認が必要"
          else
            $next + " / eval-cmd がないため保守的に判定。自動テストを追加するか手動確認が必要"
          end)
  ' "${EVAL_DIR}/codex-${ITER}.json" > "$TMP_EVAL" && mv "$TMP_EVAL" "${EVAL_DIR}/codex-${ITER}.json"
  echo "[codex-evaluate] eval_cmd が未設定かつ confidence < 0.8 の complete を incomplete に格下げ" >> "$LOG_FILE"
fi

# Codex の verdict に応じてフラグファイルを書き出す（Claude オーケストレータへの通知用）
CODEX_VERDICT=$(jq -r '.verdict // "incomplete"' "${EVAL_DIR}/codex-${ITER}.json")

# 前回のフラグを削除してから新しいフラグを書き出す
rm -f .goal-dual/CLAUDE_FINAL_CHECK_NEEDED .goal-dual/STOP_HUMAN_CANDIDATE

case "$CODEX_VERDICT" in
  complete)
    # Codex が complete を返した場合のみ Claude Final Check が必要
    printf '1\n' > .goal-dual/CLAUDE_FINAL_CHECK_NEEDED
    echo "[codex-evaluate] Codex verdict=complete: CLAUDE_FINAL_CHECK_NEEDED フラグを書き出し" >> "$LOG_FILE"
    ;;
  blocked|regressed)
    # blocked または regressed の場合は人手確認候補
    printf '1\n' > .goal-dual/STOP_HUMAN_CANDIDATE
    echo "[codex-evaluate] Codex verdict=${CODEX_VERDICT}: STOP_HUMAN_CANDIDATE フラグを書き出し" >> "$LOG_FILE"
    ;;
  *)
    # incomplete などその他は何もしない
    echo "[codex-evaluate] Codex verdict=${CODEX_VERDICT}: フラグなし" >> "$LOG_FILE"
    ;;
esac
