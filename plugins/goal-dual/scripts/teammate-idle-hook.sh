#!/usr/bin/env bash
# teammate-idle-hook.sh — TeammateIdle フックスクリプト
# 配置先: .goal-dual/hooks/teammate-idle-hook.sh（init.sh が自動コピー）
# settings.json の hooks.TeammateIdle から呼ばれる
#
# 役割:
#   チームメンバーが idle になろうとする際に、リーダーへの応答を送らずに
#   idle 入りしようとしている場合（= バグで黙り込んだ場合）を検知し、
#   exit 2 + stderr フィードバックでメンバーに応答を促す。
#
# 入力: 標準入力に JSON
#   { "team_name": "...", "member_name": "...", "idle_reason": "..." }
# 出力:
#   exit 0 → 正常 idle（応答済み）。スルーする
#   exit 2 → 応答未送信 idle 検知。フィードバックを stderr に出力してメンバーを継続させる
#
# 注意: TeammateIdle はメンバー宛のフックであり、リーダーを直接起こすものではない。
#        リーダーを起こすメインの手段は、メンバーが完了時に SendMessage(to="leader") を
#        発行すること。本フックはその保険（黙って止まるメンバーへの強制再送）として動作する。
set -euo pipefail

STATE=".goal-dual/state.json"

# goal-dual が動いていない場合はスルー
[ -f "$STATE" ] || exit 0

# 標準入力から JSON を読む
INPUT=$(cat)
MEMBER=$(echo "$INPUT" | jq -r '.member_name // empty' 2>/dev/null || true)

# メンバー名が取れない場合はスルー
[ -z "$MEMBER" ] && exit 0

# 現在の phase と pending_from を取得
PHASE=$(jq -r '.agent_teams_phase // "init"' "$STATE" 2>/dev/null || echo "init")
# pending_from はカンマ区切り文字列に変換して検索する
PENDING=$(jq -r '(.agent_teams_pending_from // []) | join(",")' "$STATE" 2>/dev/null || true)

# goal-dual の対象メンバーか確認（関係ないチームのメンバーはスルー）
case "$MEMBER" in
  implementer-team|claude-evaluator-team)
    : # 処理対象
    ;;
  *)
    exit 0  # goal-dual 以外のチームメンバーはスルー
    ;;
esac

# pending_from にこのメンバーが含まれているかチェック
# 含まれている = リーダーへの応答を送らずに idle 入りしようとしている = バグ
if echo "$PENDING" | grep -q "$MEMBER"; then
  # 応答を送っていないのに idle になろうとしている → exit 2 でフィードバック
  echo "[teammate-idle-hook] ${MEMBER} が応答を送らずに idle になろうとしています。" \
       "(phase=${PHASE}, pending=${PENDING})" >&2
  echo "あなた（${MEMBER}）はリーダーへの応答（SendMessage(to=\"leader\", ...)）を" \
       "まだ送っていません。以下の形式で応答を送ってから idle になってください:" >&2
  case "$MEMBER" in
    implementer-team)
      echo "  成功: 'implemented: <変更ファイル一覧（スペース区切り）>'" >&2
      echo "  失敗: 'codex_failed'" >&2
      ;;
    claude-evaluator-team)
      echo "  形式: 'evaluated: complete|incomplete|regressed'" >&2
      ;;
  esac
  exit 2  # メンバーに継続を促す
fi

# pending_from に含まれていない = 応答済みの正常 idle
echo "[teammate-idle-hook] ${MEMBER} が応答済みで idle になります。正常。" \
     "(phase=${PHASE})" >&2
exit 0
