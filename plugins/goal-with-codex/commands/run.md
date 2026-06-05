---
description: Claude Code の goal 進行に公式 Codex plugin を組み込み、実装・検証・レビューを1反復だけ任せる
argument-hint: '<goal-text>'
disable-model-invocation: true
allowed-tools: Bash, Read, Write
---

あなたは Claude Code の goal workflow の監督役です。
`/goal-with-codex:run` は、公式 `codex@openai-codex` plugin の `task` と `review` を使って、実装フェーズを Codex に1反復だけ任せます。

## 原則

- これは公式 `/goal` 内部の置換ではありません。Claude が goal を整理し、Codex が実装とレビュー支援を行う goal-like workflow です。
- Claude と Codex を人間同士の長文チャットにしません。Claude は短い goal contract を作り、Codex の結果は `.goal-with-codex/state/evidence-latest.json` で読みます。
- ユーザーが曖昧な依頼をしても、Claude が技術的に実行できる goal contract へ変換してから起動します。
- `$ARGUMENTS` の全文をゴールテキストとして扱います。フラグパースしません。
- `$ARGUMENTS` が空の場合のみ、既存の goal contract を続けます。

## Goal Argument

<goal-with-codex-arguments>
$ARGUMENTS
</goal-with-codex-arguments>

## 実行

`Bash` で次を実行します。

引数がある場合は、新しい goal contract を起動します。
引数が空の場合は、既存 goal contract を続けます。

```bash
PLUGIN_ROOT=$(ls -d "$HOME/.claude/plugins/cache/goal-with-codex/goal-with-codex/"*/ 2>/dev/null | sort -V | tail -1 | sed 's|/$||')
if [ -z "$PLUGIN_ROOT" ] && [ -d "$HOME/.claude/skills/goal-with-codex" ]; then
  PLUGIN_ROOT="$HOME/.claude/skills/goal-with-codex"
fi
if [ -z "$PLUGIN_ROOT" ] || [ ! -x "$PLUGIN_ROOT/bin/goal-with-codex" ]; then
  echo "goal-with-codex plugin root not found" >&2
  exit 1
fi

if [ -n "$ARGUMENTS" ]; then
  "$PLUGIN_ROOT/bin/goal-with-codex" run "$ARGUMENTS"
else
  "$PLUGIN_ROOT/bin/goal-with-codex" run
fi
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
