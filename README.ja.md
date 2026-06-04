# goal-dual

**Claude Code の `/goal` の実装ステップだけを Codex に任せるプラグインです。**

goal-dual は、Claude Code の goal-driven な進め方は好きだけれど、毎回 Claude にコード調査・実装・テストログ読解まで背負わせるとコンテキスト消費が重い、という人のための小さなプラグインです。

Claude はゴール進行と最終判断を担当します。Codex はコード調査と実装を担当します。goal-dual は、Claude が読むための短い evidence を返します。

## これは何か

goal-dual は、汎用のマルチエージェント基盤ではありません。

やることは1つです。

```text
Claude /goal が次にやることを決める
        ↓
goal-dual が Codex に実装を1ステップ委譲する
        ↓
検出できる評価コマンドがあればローカルで実行する
        ↓
Claude が .goal-dual/state/evidence-latest.json だけを読む
```

Claude に長い実装ログを読ませず、責任と判断は Claude / ユーザー側に残します。

## 向いている人

- Claude Code の `/goal` を使っている
- 実装作業は Codex に任せたい
- Claude には短い結果だけ読ませたい
- 危ない変更、高リスク判断、scope違反では止まってほしい

## 向いていない用途

- dynamic workflow への Codex 混在
- 長時間のマルチエージェント会話
- push / PR まで完全自動化
- 本番影響の大きい変更を人間レビューなしで進めること

dynamic workflow + Codex は別プラグインで扱う方針です。このリポジトリは `/goal` への Codex 委譲だけに絞ります。

## インストール

```text
/install codex@openai-codex
/plugin marketplace add khr8959/goal-dual-plugin
/plugin install goal-dual@goal-dual
/reload-plugins
```

まず診断します。

```text
/goal-dual:doctor
```

## クイックスタート

Claude Code で次のように実行します。

```text
/goal-dual:run 公開APIを変えずに、落ちているログインバリデーションテストを直す。
```

各ステップの後、goal-dual は次のファイルを作ります。

```text
.goal-dual/state/evidence-latest.json
```

Claude はこの evidence を見て、次のどれかを判断します。

- 引数なしで `/goal-dual:run` をもう一度実行する
- ゴール完了と判断する
- ユーザーに確認して止まる

## コマンド

| コマンド | 用途 |
|---|---|
| `/goal-dual:run <ゴール>` | ゴールを開始し、Codex に実装を1ステップ委譲する |
| `/goal-dual:run` | 同じゴールで Codex に次の1ステップを委譲する |
| `/goal-dual:status` | 最新 evidence と次アクションを表示する |
| `/goal-dual:dashboard [port]` | ローカルの進捗ダッシュボードを起動する |
| `/goal-dual:doctor` | Codex 委譲が使える状態か診断する |

## evidence

Claude が読む中心ファイルは意図的に小さくしています。

```json
{
  "schema": "goal-dual.evidence.v1",
  "status": "awaiting_claude_review",
  "iteration": 1,
  "codex": {
    "status": "implemented",
    "summary": "...",
    "risk": "low",
    "next_action": "..."
  },
  "eval": {
    "exit_code": 0,
    "label": "passed",
    "output_ref": ".goal-dual/state/eval-output.log"
  },
  "changed_files": ["..."],
  "next_action": "Claude reviews the evidence and decides the next /goal step."
}
```

Claude と Codex は人間同士のように長文会話しません。typed request、typed result、短い evidence でつなぎます。

## 安全設計

- 既定では commit を作成しません
- ブランチを自動作成しません
- 初回開始時に作業ツリーが dirty なら止まります
- 2回目以降は、前回の Codex 変更を残したまま続行できます
- 変更禁止範囲に触れたら既定で止まります
- Codex が `risk=high` を返したら既定で止まります
- テストログは AI コンテキストに戻す前にマスクします

## 要件

- Claude Code
- Node.js 18 以上
- `jq`
- `git`
- OpenAI Codex CLI
- Claude Code の `codex@openai-codex` プラグイン

## 開発

```bash
npm test
npm run verify
```

## ライセンス

MIT
