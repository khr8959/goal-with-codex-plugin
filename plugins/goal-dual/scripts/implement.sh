#!/bin/bash
# goal-dual/scripts/implement.sh
# plan-revised.md を Codex に実装させ、変更ファイルを個別ステージングする
# exit 0: 成功（stdout に変更ファイル一覧をスペース区切りで出力）
# exit 1: 失敗（codex_failed 相当）
set -euo pipefail

SCRIPTS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPTS/lib.sh"

PLUGIN_ROOT=$(resolve_plugin_root) || exit 1
PLAN=$(cat .goal-dual/state/plan-revised.md)
ITER=$(jq -r '.iteration' .goal-dual/state.json)
LOG_FILE=".goal-dual/logs/codex-implement-${ITER}-$(date +%Y%m%d-%H%M%S).log"
mkdir -p .goal-dual/logs

OUTPUT=$(node "$PLUGIN_ROOT/scripts/codex-companion.mjs" task --write \
  "次の計画に従って実装せよ。

【制約】
- TypeScript: any 禁止、unknown で受けて絞り込む
- console.log はコミット前に削除
- 関数・コンポーネントは 200 行以内
- コメントは「なぜ」が非自明な場合のみ（日本語）
- 新規ファイルは最小限にする
- 既存パターンと整合性を保つ

【計画】
${PLAN}" </dev/null 2>&1) || true

echo "$OUTPUT" > "$LOG_FILE"

if [ -z "$OUTPUT" ] || [ "${#OUTPUT}" -lt 50 ]; then
  exit 1
fi

# 変更ファイルを個別ステージング（git add . は禁止）
CHANGED=$(git diff --name-only 2>/dev/null || echo "")
UNTRACKED=$(git ls-files --others --exclude-standard 2>/dev/null | grep -v '^\.goal-dual/' || true)
STAGED_FILES=""
for f in $CHANGED $UNTRACKED; do
  if [ -f "$f" ]; then
    git add "$f"
    STAGED_FILES="$STAGED_FILES $f"
  fi
done

echo "${STAGED_FILES# }"
