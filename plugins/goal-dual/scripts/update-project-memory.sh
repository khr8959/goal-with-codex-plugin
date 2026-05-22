#!/bin/bash
# goal-dual/scripts/update-project-memory.sh
# 停止時（STOP_STAGNANT / STOP_HUMAN）に「記憶へ追加すべき教訓」を提案する
# .goal-dual/state/memory-suggestions.md を生成する（自動で .goal-dual-memory.md は編集しない）
# exit 0: 成功 / exit 1: Codex 失敗
set -euo pipefail

SCRIPTS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPTS/lib.sh"

OUTPUT_FILE=".goal-dual/state/memory-suggestions.md"
mkdir -p "$(dirname "$OUTPUT_FILE")"

CODEX_PLUGIN_ROOT=$(resolve_codex_plugin_root) || exit 1

STOP_REASON="${1:-$(jq -r '.stop_reason // "UNKNOWN"' .goal-dual/state.json 2>/dev/null)}"
GOAL=$(cat .goal-dual/goal.md 2>/dev/null || echo "")
PROGRESS=$(tail -100 .goal-dual/progress.txt 2>/dev/null || echo "")
SYNTH_FILE=$(ls -t .goal-dual/state/evaluations/synthesized-*.json 2>/dev/null | head -1 || true)
FINAL_VERDICT=""
NEXT_ACTION=""
if [ -n "$SYNTH_FILE" ]; then
  FINAL_VERDICT=$(jq -r '.verdict // "不明"' "$SYNTH_FILE" 2>/dev/null || echo "不明")
  NEXT_ACTION=$(jq -r '.next_action // ""' "$SYNTH_FILE" 2>/dev/null || echo "")
fi

OUTPUT=$(node "$CODEX_PLUGIN_ROOT/scripts/codex-companion.mjs" task \
"以下の情報をもとに、このプロジェクトで次回 goal-dual を実行する際に役立つ教訓を抽出せよ。

【出力形式】
# goal-dual Project Memory への追加候補

## 教訓（次回以降の実行で役立つもの）

- <教訓1>
- <教訓2>
...

## 追加を推奨しない理由がある場合

（記載不要な場合は省略）

【停止理由】
${STOP_REASON}

【最終評価】
verdict: ${FINAL_VERDICT}
next_action: ${NEXT_ACTION}

【ゴール】
${GOAL}

【実行ログ（末尾 100 行）】
${PROGRESS}" \
</dev/null 2>&1) || true

{
  printf '# goal-dual-memory への追加候補\n\n'
  printf '> このファイルは自動生成されました（自動書き込みはしていません）。\n'
  printf '> 内容を確認し、必要なものだけ .goal-dual-memory.md にコピーしてください。\n\n'
  if [ -n "$OUTPUT" ] && [ "${#OUTPUT}" -gt 20 ]; then
    echo "$OUTPUT"
  else
    printf '（Codex による教訓抽出に失敗しました）\n'
  fi
} > "$OUTPUT_FILE"

echo "memory-suggestions.md を生成しました: $OUTPUT_FILE"
