#!/bin/bash
# goal-dual/scripts/scope-check.sh — enforce モードの scope_deny 強制チェック
# Usage: bash scope-check.sh <iteration>
#
# 終了コード:
#   0 = 違反なし、または enforce 無効（advisory）/ scope_deny 空 / 照合不能 → no-op
#   2 = scope_deny 違反を検知（呼び出し側は STOP_SCOPE で停止する）
#
# advisory では警告のみ、enforce では停止用の違反ファイルを書き出す。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib.sh"

STATE=".goal-dual/state.json"
ITER="${1:-$(jq -r '.iteration // 0' "$STATE" 2>/dev/null || echo 0)}"

SCOPE_MODE="${GOAL_DUAL_SCOPE_MODE:-$(state_get scope_mode)}"
SCOPE_MODE="${SCOPE_MODE:-advisory}"
if [ "$SCOPE_MODE" != "enforce" ]; then
  exit 0
fi

SCOPE_DENY=$(jq -r '.scope_deny // [] | .[]' "$STATE" 2>/dev/null || true)
if [ -z "$SCOPE_DENY" ]; then
  exit 0
fi

NO_GIT=$(jq -r '.no_git // false' "$STATE" 2>/dev/null || echo false)

# 変更ファイル一覧を算出
if [ "$NO_GIT" = "true" ]; then
  if [ ! -f .goal-dual/.started ]; then
    # 基準ファイルが無く照合不能 → advisory フォールバック
    exit 0
  fi
  CHANGED_LIST=$(find . -newer .goal-dual/.started \
    -not -path './.goal-dual/*' \
    -not -path './.git/*' -type f 2>/dev/null | sed 's|^\./||' | sort -u | grep -v '^$' || true)
else
  BASE=$(jq -r '.base_branch // ""' "$STATE" 2>/dev/null || echo "")
  CHANGED_LIST=$(
    {
      [ -n "$BASE" ] && git diff --name-only "${BASE}...HEAD" 2>/dev/null
      git diff --cached --name-only 2>/dev/null
      git diff --name-only 2>/dev/null
      git ls-files --others --exclude-standard 2>/dev/null
    } | grep -v '^\.goal-dual/' | sort -u | grep -v '^$' || true
  )
fi

if [ -z "$CHANGED_LIST" ]; then
  exit 0
fi

# scope_deny パターンとの照合（単純な grep -iF マッチング）
VIOLATIONS=""
while IFS= read -r deny_pattern; do
  [ -z "$deny_pattern" ] && continue
  MATCHED=$(echo "$CHANGED_LIST" | grep -iF "$deny_pattern" || true)
  [ -n "$MATCHED" ] && VIOLATIONS="${VIOLATIONS}${MATCHED}"$'\n'
done <<< "$SCOPE_DENY"

if [ -z "$VIOLATIONS" ]; then
  exit 0
fi

# 違反を記録
VIOLATIONS=$(echo "$VIOLATIONS" | sort -u | grep -v '^$')
mkdir -p .goal-dual/state
{
  echo "iteration: $ITER"
  echo "scope_mode: enforce"
  echo "禁止パスへの変更を検知しました:"
  echo "$VIOLATIONS"
} > .goal-dual/state/scope-violations.txt

echo "[scope-enforce] 禁止パスへの変更を検知しました（停止します）:" >&2
echo "$VIOLATIONS" >&2

goal_dual_progress "scope-violation (enforce) → STOP_SCOPE" <<EOF
iteration: $ITER
違反ファイル:
$VIOLATIONS
EOF

exit 2
