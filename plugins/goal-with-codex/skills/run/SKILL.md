---
description: Claude Code の goal 進行に公式 Codex plugin を組み込み、実装・検証・レビューを1反復だけ任せる
argument-hint: '<goal-text>'
allowed-tools: Bash, Read, Write
---

あなたは Claude Code の goal workflow の監督役です。
`/goal-with-codex:run` は、公式 `codex@openai-codex` plugin の `task` と `review` を使って、実装フェーズを Codex に1反復だけ任せます。

## 原則

- これは公式 `/goal` 内部の置換ではありません。Claude が goal を整理し、Codex が実装とレビュー支援を行う goal-like workflow です。
- Claude と Codex を人間同士の長文チャットにしません。Claude は短い goal contract を作り、Codex の結果は `.goal-with-codex/state/evidence-latest.json` で読みます。
- ユーザーが曖昧な依頼をしても、Claude が技術的に実行できる goal contract へ変換してから起動します。
- ユーザーの `$ARGUMENTS` を shell コマンド文字列に直接埋め込まないでください。

## Goal Argument

<goal-with-codex-arguments>
$ARGUMENTS
</goal-with-codex-arguments>

## 新しいゴールを開始する

引数がある場合、まず `Write` で `.goal-with-codex/request/goal.md` を作成します。
ユーザーの原文を保持しつつ、Claude が技術的に正確なゴールへ整えてください。

```markdown
# User Goal
<ユーザーの依頼原文>

# Technical Goal
<このリポジトリで実装可能な、具体的で検証可能なゴール>

# Acceptance Criteria
- <完了判断に使える条件>
- <テスト、lint、ドキュメントなど必要な確認>

# Constraints
- Keep changes scoped to the requested goal.
- Do not commit, push, rename the repository, or install global tools.
- Prefer existing project patterns.

# Non-goals
- <今回やらないこと>
```

その後、`Bash` で次を実行します。

```bash
goal-with-codex run --goal-file .goal-with-codex/request/goal.md
```

## 同じゴールを続ける

引数がない場合は、同じ goal contract を続けます。

```bash
goal-with-codex run
```

## 結果の読み方

必要なら `Read` で `.goal-with-codex/state/evidence-latest.json` を読みます。

- `status = awaiting_claude_review`: Codex の実装・評価・レビューが終わった。Claude が acceptance criteria と差分を見て、完了か追加反復かを判断する
- `status = needs_fix`: 評価コマンドが失敗した。まだスコープ内なら、引数なしで `/goal-with-codex:run` を再実行する
- `status = stopped`: Codex 実行失敗、レビュー実行失敗、または人間判断が必要。evidence とログ参照を読んで止める

最後に、ユーザーには短く伝えてください。

```text
Codex goal step complete.
Status: <status>
Next: <recommendation>
Evidence: .goal-with-codex/state/evidence-latest.json
```
