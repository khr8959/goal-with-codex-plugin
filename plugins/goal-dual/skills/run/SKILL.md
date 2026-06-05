---
description: Claude /goal の実装フェーズだけを Codex に1ステップ委譲し、短い evidence を返す
argument-hint: '<goal-text>'
allowed-tools: Bash, Read, Write
---

あなたは Claude Code の `/goal` ループを軽くするための薄い監督役です。
`/goal-dual:run` は、Codex に実装を1ステップだけ委譲し、Claude が読む情報を短い evidence に圧縮します。

## 重要な制約

- 公式 `/goal` の内部実装を置き換えるのではなく、`/goal` が通常 Claude にやらせる実装 tool-use 部分を Codex へ外注する
- Claude と Codex を長文会話させない
- Claude は `.goal-dual/state/evidence-latest.json` を読んで、次の `/goal` 判断だけを行う
- ユーザーの `$ARGUMENTS` を shell コマンド文字列に直接埋め込まない

## 実行

## Goal Argument

<goal-dual-arguments>
$ARGUMENTS
</goal-dual-arguments>

引数ありで新しいゴールを開始する場合:

1. `Bash` で `.goal-dual/request/` を作成する
2. `Write` で `.goal-dual/request/goal.txt` に `<goal-dual-arguments>` 内の内容をそのまま保存する
3. `Bash` で `goal-dual run --goal-file .goal-dual/request/goal.txt` を実行する

引数なしで同じゴールを続ける場合:

```bash
goal-dual run
```

## 結果の読み方

必要なら `Read` で `.goal-dual/state/evidence-latest.json` を読みます。

- `status = awaiting_claude_review`: テストが通った、または評価コマンドがない。Claude が差分と evidence を見て完了判断する
- `status = needs_fix`: 評価コマンドが失敗。公式 `/goal` の次反復で、引数なしの `/goal-dual:run` を再実行して Codex に修正を委譲する
- `status = stopped`: scope違反、高リスク、Codex失敗、人間判断が必要な停止

最後に、ユーザーには短く伝えてください。

```text
Codex step complete.
Status: <status>
Next: <next_action>
Evidence: .goal-dual/state/evidence-latest.json
```
