#!/bin/bash
# goal-dual/scripts/review-only.sh
# 現在の変更（または指定 base との差分）を Claude + Codex 合議でレビューする
# 実装や git commit は行わない
# Usage: bash review-only.sh [base-ref] [topic]
# exit 0: レビュー完了 / exit 1: エラー
set -euo pipefail

SCRIPTS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPTS/lib.sh"

BASE_REF="${1:-}"
TOPIC="${2:-現在の変更が安全か確認する}"
REVIEW_LEVEL="${GOAL_DUAL_REVIEW_LEVEL:-standard}"
OUTPUT_DIR=".goal-dual-review"
OUTPUT_FILE="$OUTPUT_DIR/review-report.md"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
LOG_FILE="$OUTPUT_DIR/review-${TIMESTAMP}.log"

mkdir -p "$OUTPUT_DIR"

# --- 必須コマンドチェック ---
for cmd in jq node; do
  command -v "$cmd" >/dev/null || { echo "$cmd が必要です" >&2; exit 1; }
done
command -v codex >/dev/null || { echo "codex CLI が必要です" >&2; exit 1; }

# --- git モード確認 ---
NO_GIT=true
if command -v git >/dev/null 2>&1 && git rev-parse --git-dir >/dev/null 2>&1; then
  NO_GIT=false
fi

# --- base ref 解決 ---
if [ -z "$BASE_REF" ] && [ "$NO_GIT" = "false" ]; then
  if git rev-parse --verify origin/main >/dev/null 2>&1; then
    BASE_REF="origin/main"
  elif git rev-parse --verify main >/dev/null 2>&1; then
    BASE_REF="main"
  elif git rev-parse --verify master >/dev/null 2>&1; then
    BASE_REF="master"
  else
    BASE_REF="HEAD~1"
  fi
fi

# --- 変更ファイル・差分を収集 ---
DIFF_STAT=""
DIFF_FILES=""
DIFF_CONTENT=""

if [ "$NO_GIT" = "false" ]; then
  DIFF_STAT=$(git diff --stat "${BASE_REF}...HEAD" 2>/dev/null || git diff --stat 2>/dev/null || echo "(変更なし)")
  DIFF_FILES=$(git diff --name-only "${BASE_REF}...HEAD" 2>/dev/null \
    || git diff --name-only 2>/dev/null || echo "")
  # 差分の最初の 200 行のみ（大きすぎる場合の対策）
  DIFF_CONTENT=$(git diff "${BASE_REF}...HEAD" 2>/dev/null \
    || git diff 2>/dev/null | head -200 || echo "")
else
  DIFF_FILES="(no-git モード: ファイル一覧取得不可)"
  DIFF_STAT="(no-git モード)"
fi

# --- Codex レビュー ---
CODEX_PLUGIN_ROOT=$(resolve_codex_plugin_root) || exit 1

echo "Codex レビューを実行中..."
CODEX_OUTPUT=$(node "$CODEX_PLUGIN_ROOT/scripts/codex-companion.mjs" task \
"以下の変更をコードレビューせよ。実装は変更しない。

【レビュー観点】
- Critical: セキュリティ問題（インジェクション・認証欠陥・機密漏洩など）
- Warning: 設計・品質・バグリスク
- Suggestion: 改善案・可読性

【トピック】
${TOPIC}

【変更統計】
${DIFF_STAT}

【変更ファイル一覧】
${DIFF_FILES}

【差分（先頭 200 行）】
${DIFF_CONTENT}" \
</dev/null 2>&1) || true

echo "$CODEX_OUTPUT" > "$LOG_FILE"

# --- レポート生成 ---
{
  echo "# goal-dual-review レポート"
  echo ""
  echo "**日時:** $(date)"
  echo "**トピック:** ${TOPIC}"
  echo "**base:** ${BASE_REF:-（未指定）}"
  echo "**review-level:** ${REVIEW_LEVEL}"
  echo ""
  echo "---"
  echo ""
  echo "## 変更統計"
  echo ""
  echo "$DIFF_STAT"
  echo ""
  echo "## 変更ファイル一覧"
  echo ""
  echo "$DIFF_FILES"
  echo ""
  echo "## Codex レビュー結果"
  echo ""
  echo "$CODEX_OUTPUT"
  echo ""
  echo "---"
  echo ""
  echo "## 判定サマリ"
  echo ""
  if echo "$CODEX_OUTPUT" | grep -qiE "Critical:|CRITICAL|🚨"; then
    echo "**Critical 指摘あり** — commit 前に対処を推奨します。"
  elif echo "$CODEX_OUTPUT" | grep -qiE "Warning:|WARNING|⚠️"; then
    echo "**Warning あり** — 確認・対処を検討してください。"
  else
    echo "**重大な問題なし** — commit して問題ない可能性が高いです。"
  fi
  echo ""
  echo "---"
  echo "*このレポートは review-only モードで生成されました。コードの変更や commit は行っていません。*"
} > "$OUTPUT_FILE"

echo ""
echo "=== goal-dual-review 完了 ==="
echo "レポート: $OUTPUT_FILE"
