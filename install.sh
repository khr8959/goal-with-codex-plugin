#!/bin/bash
# goal-dual プラグインのインストールスクリプト
# Usage: bash install.sh
set -euo pipefail

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="$HOME/.claude"

echo "=== goal-dual プラグインをインストールします ==="
echo ""

# 必須コマンドチェック
for cmd in jq node; do
  command -v "$cmd" >/dev/null || { echo "エラー: $cmd が必要です" >&2; exit 1; }
done

# codex CLI チェック
if ! command -v codex >/dev/null 2>&1; then
  echo "警告: codex CLI が見つかりません。"
  echo "  npm install -g @openai/codex  でインストールしてください。"
  echo ""
fi

# codex@openai-codex プラグインチェック
if ! ls "$CLAUDE_DIR/plugins/cache/openai-codex/codex/"*"/scripts/codex-companion.mjs" >/dev/null 2>&1; then
  echo "警告: codex@openai-codex プラグインが見つかりません。"
  echo "  Claude Code で /install codex@openai-codex を実行してください。"
  echo ""
fi

# 1. commands をコピー
echo "[1/3] コマンドをインストール中..."
mkdir -p "$CLAUDE_DIR/commands"
for f in "$PLUGIN_DIR/plugins/goal-dual/commands/"*.md; do
  base="$(basename "$f")"
  case "$base" in
    run.md) target="goal-dual.md" ;;
    doctor.md) target="goal-dual-doctor.md" ;;
    dashboard.md) target="goal-dual-dashboard.md" ;;
    status.md) target="goal-dual-status.md" ;;
    *) target="$base" ;;
  esac
  cp "$f" "$CLAUDE_DIR/commands/$target"
  echo "  -> $CLAUDE_DIR/commands/$target"
done

# 2. agents をコピー（v2 は追加エージェントなし）
echo "[2/3] エージェントを確認中..."
mkdir -p "$CLAUDE_DIR/agents"
shopt -s nullglob
agent_files=("$PLUGIN_DIR/plugins/goal-dual/agents/"*.md)
if [ "${#agent_files[@]}" -eq 0 ]; then
  echo "  -> 追加エージェントなし"
else
  for f in "${agent_files[@]}"; do
    cp "$f" "$CLAUDE_DIR/agents/"
    echo "  -> $CLAUDE_DIR/agents/$(basename "$f")"
  done
fi
shopt -u nullglob

# 3. scripts をコピー
echo "[3/3] スクリプトをインストール中..."
mkdir -p "$CLAUDE_DIR/goal-dual/scripts"
shopt -s nullglob
script_files=("$PLUGIN_DIR/plugins/goal-dual/scripts/"*.sh "$PLUGIN_DIR/plugins/goal-dual/scripts/"*.mjs)
for f in "${script_files[@]}"; do
  cp "$f" "$CLAUDE_DIR/goal-dual/scripts/"
  chmod +x "$CLAUDE_DIR/goal-dual/scripts/$(basename "$f")"
  echo "  -> $CLAUDE_DIR/goal-dual/scripts/$(basename "$f")"
done
shopt -u nullglob

echo ""
echo "=== インストール完了 ==="
echo ""
echo "使い方:"
echo "  まず診断: /goal-dual:doctor"
echo "  ダッシュボード: /goal-dual:dashboard"
echo "  Marketplace: /goal-dual:run <ゴールテキスト>"
echo "  状態確認: /goal-dual:status"
echo "  手動install: /goal-dual <ゴールテキスト>"
echo ""
echo "例:"
echo "  /goal-dual:run ユーザー認証機能を追加する。JWT でアクセストークンを発行し、/api/me エンドポイントを保護する。"
echo ""
echo "環境変数（任意）:"
echo "  GOAL_DUAL_SCOPE_MODE=enforce|advisory           （デフォルト: enforce）"
echo "  GOAL_DUAL_ALLOW_HIGH_RISK=1                     （デフォルト: 0）"
