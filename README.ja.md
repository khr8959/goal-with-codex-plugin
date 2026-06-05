# goal-with-codex

`goal-with-codex` は、Claude Code の goal 的な進行に、公式 `codex@openai-codex` plugin を組み込むための plugin skill です。

Codex を自作で再実装しません。Claude Code の非公開な `/goal` 内部にもパッチしません。Claude が曖昧な依頼を技術的に正確な goal contract に整え、driver が公式 Codex plugin に1反復の実装・評価・レビューを任せ、最後に Claude が読む短い evidence を作ります。

## なぜ作るのか

Claude Code の goal-driven な進め方は便利です。ただ、毎回 Claude がコード調査、編集、テストログ読解、レビューまで全部やると、コンテキスト消費が重くなります。

Codex はすでにコードベース内の実装やレビューに強いので、この plugin では Codex を「実装担当」として公式plugin経由で呼びます。

1. Claude が `.goal-with-codex/request/goal.md` に goal contract を作る
2. `goal-with-codex` が `codex-companion.mjs task --write --json` を呼ぶ
3. driver が `npm test`、`pytest`、`go test ./...` など検出できる評価コマンドを実行する
4. 評価が通る、または評価コマンドがなければ Codex `review` を呼ぶ
5. Claude が `.goal-with-codex/state/evidence-latest.json` を読んで、完了か継続かを判断する

責任はClaude側に残し、実装反復だけCodexへ寄せます。

## 想定ユーザー

AIエージェントに自走してほしいが、責任まで完全に手放したくない人向けです。

- Claude Code で長めの実装を進める個人開発者
- Claude のコンテキスト消費を抑えたい plugin / tooling 作者
- `/goal` 的な進め方は好きだが、実装部分は Codex に任せたいエンジニア
- AI変更を受け入れる前に、止まる場所と evidence が欲しいチーム

汎用マルチエージェント基盤、dynamic workflow engine、AI同士のチャット中継ではありません。

## インストール

先に Claude Code で公式 Codex plugin を入れてください。その後、このpluginを入れます。

```text
/plugin marketplace add khr8959/goal-with-codex-plugin
/plugin install goal-with-codex@goal-with-codex
```

ローカル開発では:

```bash
npm run install-local
```

## コマンド

| コマンド | 役割 |
| --- | --- |
| `/goal-with-codex:doctor` | 依存関係と公式Codex pluginを診断する |
| `/goal-with-codex:run <goal>` | goal contract を作り、Codexで1反復進める |
| `/goal-with-codex:run` | 同じゴールを続け、前回のCodex threadをresumeする |
| `/goal-with-codex:status` | 現在状態と最新evidenceを表示する |
| `/goal-with-codex:dashboard` | 進捗ダッシュボードを起動する |

## Evidence

主な出力はここです。

```text
.goal-with-codex/state/evidence-latest.json
```

status、recommendation、Codex task、review、評価結果、変更ファイル、次のコマンドが入ります。Claude は毎回フルログを読むのではなく、この短い evidence を読んで次の判断をします。

## 開発

```bash
npm run verify
```

テストでは公式Codex plugin境界をstub化し、routing、resume、evidence生成、goal-file経由の安全な引き渡しを確認します。
