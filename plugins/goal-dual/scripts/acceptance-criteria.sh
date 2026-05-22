#!/bin/bash
# goal-dual/scripts/acceptance-criteria.sh
# ゴール本文から受け入れ条件を生成し acceptance-criteria.md に保存する
# 再開時（ファイルが既存）はスキップする
# exit 0: 成功 / exit 1: Codex 失敗（フォールバック生成済み）
set -euo pipefail

SCRIPTS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPTS/lib.sh"

OUTPUT_FILE=".goal-dual/state/acceptance-criteria.md"
mkdir -p "$(dirname "$OUTPUT_FILE")"

# 再開時はスキップ
if [ -f "$OUTPUT_FILE" ]; then
  echo "acceptance-criteria.md は既存（再開）: スキップ"
  exit 0
fi

CODEX_PLUGIN_ROOT=$(resolve_codex_plugin_root) || exit 1
GOAL=$(cat .goal-dual/goal.md 2>/dev/null || echo "")

OUTPUT=$(node "$CODEX_PLUGIN_ROOT/scripts/codex-companion.mjs" task \
"以下のゴールを達成したと判断できる受け入れ条件を 3〜7 個の箇条書きで出力せよ。

【制約】
- 専門用語を避け、非エンジニアにも分かる言葉で書く
- 「〜が動作する」「〜が確認できる」「〜が壊れない」の形を基本にする
- 3 個以上 7 個以下に収める
- 余計な前置き・説明なし。箇条書きのみ出力（「- 」で始まる行のみ）

【ゴール】
${GOAL}" \
</dev/null 2>&1) || true

if [ -n "$OUTPUT" ] && echo "$OUTPUT" | grep -qE "^[-*]"; then
  {
    printf '## 完了条件\n\n'
    echo "$OUTPUT" | grep -E "^[-*]"
  } > "$OUTPUT_FILE"
  echo "acceptance-criteria.md を生成しました"
  exit 0
else
  # Codex 失敗時のフォールバック
  {
    printf '## 完了条件\n\n'
    printf '- ゴールに記載された機能が動作する\n'
    printf '- 既存の動作が壊れない\n'
    printf '- テスト（または目視確認）が可能な状態になっている\n'
  } > "$OUTPUT_FILE"
  echo "acceptance-criteria.md をデフォルトテンプレートで生成しました（Codex 出力なし）"
  exit 0
fi
