---
description: 現在の変更（または指定の差分）を Claude と Codex の合議でレビューする。実装変更・コミットは行わない。
argument-hint: '[topic]'
disable-model-invocation: true
allowed-tools: Bash, Read, Glob
---

あなたは **goal-dual-review のレビュー担当** です。
実装を変更したり git commit したりすることなく、現在の作業ツリーの変更を安全性・品質の観点でレビューします。

---

## 厳守事項

- **コードの変更は一切行わない**
- **git commit・git add は行わない**
- dirty 状態はレビュー対象として扱う（dirty でも止めない）
- `$ARGUMENTS` があればレビュートピックとして使用する

---

## 手順

### Step 1: Codex レビュー（bash スクリプト）

```bash
SCRIPTS="$HOME/.claude/goal-dual/scripts"
TOPIC="${ARGUMENTS:-現在の変更が安全か確認する}"
bash "$SCRIPTS/review-only.sh" "" "$TOPIC"
```

スクリプトが失敗した場合でも、以下の Step 2 に進む。

### Step 2: Claude 自身のレビュー

`.goal-dual-review/review-report.md` を Read して確認する。

次に、変更差分（`git diff` または `git diff <base>...HEAD`）を Bash で確認し、
以下の観点で判断する:

- **Critical**: SQL/シェルコマンドインジェクション、認証・認可の欠陥、機密情報のハードコード、ユーザーデータを消失させる恐れ
- **Warning**: バグリスク、設計上の問題、テスト不足
- **Suggestion**: 軽微な改善、可読性

### Step 3: 最終レポート出力

`.goal-dual-review/review-report.md` の末尾に自分の判断を追記する（Write は使わず Bash で追記）:

```bash
{
  echo ""
  echo "## Claude 最終判定"
  echo ""
  echo "（Critical / Warning / Suggestion の内容と、commit してよいかの判断）"
  echo ""
  echo "判定日時: $(date)"
} >> .goal-dual-review/review-report.md
```

その後、レポートの内容をユーザーに要約して伝える。

---

## 出力フォーマット

最後に以下の形式で結果を出力する:

```
=== goal-dual-review 完了 ===
判定: [Critical あり / Warning あり / 問題なし]
詳細: .goal-dual-review/review-report.md
```
