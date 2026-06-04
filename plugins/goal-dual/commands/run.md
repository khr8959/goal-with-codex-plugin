---
description: Claude /goal の実装フェーズだけを Codex に1ステップ委譲する
argument-hint: '<goal-text>'
allowed-tools: Bash, Read
---

あなたは Claude Code の `/goal` ループを軽くするための薄い監督役です。
`/goal-dual:run` は、Codex に実装を1ステップだけ委譲し、Claude が読む情報を短い evidence に圧縮します。

## 役割

- Codex: コード調査、実装、自己レビュー
- shell: 検出された評価コマンドの実行
- Claude: `.goal-dual/state/evidence-latest.json` だけを読み、公式 `/goal` ループとして次に進むか止まるか判断

Claude と Codex を長文会話させないでください。Codex への依頼と結果は JSON / evidence として扱います。

## 実行

まず scripts ディレクトリを解決します。

```bash
SCRIPTS="${CLAUDE_PLUGIN_ROOT:+$CLAUDE_PLUGIN_ROOT/scripts}"
if [ -z "${SCRIPTS:-}" ] || [ ! -d "$SCRIPTS" ]; then
  SCRIPTS=$(jq -r '.goal_dual_plugin_root // empty' .goal-dual/state.json 2>/dev/null | sed 's|$|/scripts|')
fi
if [ -z "${SCRIPTS:-}" ] || [ ! -d "$SCRIPTS" ]; then
  SCRIPTS=$(ls -d "$HOME/.claude/plugins/cache/goal-dual/goal-dual/"*/scripts 2>/dev/null | sort -V | tail -1)
fi
if [ -z "${SCRIPTS:-}" ] || [ ! -d "$SCRIPTS" ]; then
  SCRIPTS="$HOME/.claude/goal-dual/scripts"
fi
```

次に1ステップだけ委譲します。

```bash
bash "$SCRIPTS/delegate-step.sh" "$ARGUMENTS"
```

## 結果の読み方

実行後、必要なら `Read` で `.goal-dual/state/evidence-latest.json` を読みます。

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
