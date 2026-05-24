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
  cp "$f" "$CLAUDE_DIR/commands/"
  echo "  -> $CLAUDE_DIR/commands/$(basename "$f")"
done

# 2. agents をコピー
echo "[2/3] エージェントをインストール中..."
mkdir -p "$CLAUDE_DIR/agents"
for f in "$PLUGIN_DIR/plugins/goal-dual/agents/"*.md; do
  cp "$f" "$CLAUDE_DIR/agents/"
  echo "  -> $CLAUDE_DIR/agents/$(basename "$f")"
done

# 3. scripts をコピー
echo "[3/3] スクリプトをインストール中..."
mkdir -p "$CLAUDE_DIR/goal-dual/scripts"
for f in "$PLUGIN_DIR/plugins/goal-dual/scripts/"*.sh; do
  cp "$f" "$CLAUDE_DIR/goal-dual/scripts/"
  chmod +x "$CLAUDE_DIR/goal-dual/scripts/$(basename "$f")"
  echo "  -> $CLAUDE_DIR/goal-dual/scripts/$(basename "$f")"
done

echo ""
echo "=== インストール完了 ==="
echo ""
echo "使い方:"
echo "  /goal-dual <ゴールテキスト>"
echo ""
echo "例:"
echo "  /goal-dual ユーザー認証機能を追加する。JWT でアクセストークンを発行し、/api/me エンドポイントを保護する。"
echo ""
echo "環境変数（任意）:"
echo "  GOAL_DUAL_REVIEW_LEVEL=strict|standard|relaxed  （デフォルト: standard）"
echo "  GOAL_DUAL_STAGNATION_THRESHOLD=3                （デフォルト: 3）"
