#!/bin/bash
# goal-dual/scripts/explain-stop.sh — stop_reason に応じた復旧手順を表示する
set -euo pipefail

STATE=".goal-dual/state.json"

if [ ! -f "$STATE" ]; then
  echo "goal-dual の停止状態はありません。"
  exit 0
fi

reason=$(jq -r '.stop_reason // "UNKNOWN"' "$STATE" 2>/dev/null || echo "UNKNOWN")
iteration=$(jq -r '.iteration // 0' "$STATE" 2>/dev/null || echo "0")

echo "=== goal-dual stop explanation ==="
echo ""
echo "Stop reason : $reason"
echo "Iteration   : $iteration"
echo ""

case "$reason" in
  COMPLETE)
    echo "完了しています。"
    echo ""
    echo "確認するもの:"
    echo "- .goal-dual/state/final-report.md または .goal-dual-archive/.../state/final-report.md"
    echo "- .goal-dual/state/final-review.md"
    echo "- git diff"
    echo ""
    echo "既定では commit / push / PR は作成されません。差分を確認してから手動で進めてください。"
    ;;
  STOP_DIRTY)
    echo "作業ツリーに goal-dual 以外の未コミット変更があったため停止しました。"
    echo ""
    echo "次にやること:"
    echo "- 既存変更を commit / stash する"
    echo "- その後、同じ /goal-dual:run を再実行する"
    ;;
  STOP_SCOPE)
    echo "変更禁止パスへの変更を検知したため停止しました。これは安全機能です。"
    echo ""
    echo "確認するもの:"
    echo "- .goal-dual/state/scope-violations.txt"
    echo "- .goal-dual/progress.txt"
    echo "- git diff"
    echo ""
    echo "次にやること:"
    echo "- 該当変更を戻す"
    echo "- scope を広げてよいなら plan/scope を見直す"
    echo "- 再開する場合は同じ /goal-dual:run を実行する"
    ;;
  STOP_STAGNANT)
    echo "同じ verdict が続き、進捗がないと判断したため停止しました。"
    echo ""
    echo "確認するもの:"
    echo "- .goal-dual/state/evaluations/synthesized-*.json"
    echo "- .goal-dual/progress.txt"
    echo ""
    echo "次にやること:"
    echo "- ゴールをより具体化する"
    echo "- テスト失敗や未解決条件を人間が確認する"
    echo "- 必要なら /goal-dual:plan で計画を作り直す"
    ;;
  STOP_HUMAN)
    echo "人間の判断が必要な状態です。goal-dual が安全側に止まりました。"
    echo ""
    echo "確認するもの:"
    echo "- .goal-dual/state/final-report.md"
    echo "- .goal-dual/progress.txt"
    echo "- .goal-dual/state/evaluations/"
    echo "- git diff"
    echo ""
    echo "よくある原因:"
    echo "- Codex が blocked / risk=high を返した"
    echo "- レビューで Critical または判定不能になった"
    echo "- commit / snapshot / eval 周辺で安全に続行できない失敗が起きた"
    ;;
  *)
    echo "停止理由が未設定または未知です。"
    echo ""
    echo "確認するもの:"
    echo "- .goal-dual/state.json"
    echo "- .goal-dual/progress.txt"
    echo "- .goal-dual/logs/"
    ;;
esac
