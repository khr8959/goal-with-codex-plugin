# goal-dual プラグイン

goal-dual は、Claude Code 上で OpenAI Codex プラグインを反復開発ワークフローに組み込むためのプラグインです。
Claude が全体を進行管理し、Codex がコード調査・実装・一次評価を担当します。

## 役割分担

| 役割 | 担当 |
|---|---|
| オーケストレーション・最終判断 | Claude |
| ゴール整理・完了条件定義 | Claude |
| コード調査・実装 | OpenAI Codex plugin |
| 一次評価 | OpenAI Codex plugin |
| テスト実行 | shell |

## ワークフロー

具体的なゴールが決まっている場合は、`/goal-dual <ゴール>` と入力するだけで、以下の5ステップを自律的に繰り返します:

1. **Claude がゴールを整理する** — ゴールから受け入れ条件・変更範囲・タスク分割を決定する
2. **goal-dual が OpenAI Codex プラグインへ作業を依頼する** — 計画を Codex に渡し、実装を委譲する
3. **Codex がコードを調べて実装する** — コードベースを探索し、変更を加える
4. **テストを実行する** — `npm test` / `pytest` などの eval コマンドを自動実行する
5. **Codex が一次判定し、Claude が続行または完了を判断する** — 受け入れ条件を満たしていれば完了、そうでなければ次のイテレーションへ

ゴールの書き方に迷う場合は、先に `/goal-dual-plan <相談内容>` を使います。
`/goal-dual-plan` は実装を開始せず、`.goal-dual/plan/` に実行計画・完了条件・確認事項を作ります。
計画が ready になった後、引数なしで `/goal-dual` を実行すると、その plan を読んで実装を開始します。

## 要件

- Claude Code（最新版）
- Node.js 18 以上
- `jq`
- `git`
- [codex CLI](https://github.com/openai/codex): `npm install -g @openai/codex`
- Claude Code の `codex@openai-codex` プラグイン（Claude Code 内で `/install codex@openai-codex`）

## インストール方法（推奨）

Claude Code 内で以下を実行します:

```text
/plugin marketplace add khr8959/goal-dual-plugin
/plugin install goal-dual@goal-dual
/reload-plugins
```

Marketplace 経由でインストールすると、Claude Code がプラグインをローカルキャッシュへ配置します。
ユーザーの作業プロジェクト内に `goal-dual-plugin/` を手動で clone する必要はありません。

これで以下が利用できます:

- `/goal-dual`（継続実装）
- `/goal-dual-plan`（初心者向けの goal 整理）
- `/goal-dual-review`（レビューのみ）
- `/goal-dual-history`（履歴表示）
- `/goal-dual-route`（ルーティングのみ）

### 手動インストール（開発者向け）

プラグイン自体を開発・検証する場合のみ、リポジトリを clone して手動インストールします。

```bash
cd ~/Documents/GitHub
git clone https://github.com/khr8959/goal-dual-plugin.git
cd goal-dual-plugin
bash install.sh
```

`git clone` は、まだ `goal-dual-plugin` ディレクトリの中にいない場所で実行してください。
既存の `goal-dual-plugin` ディレクトリ内で再度 clone すると、`goal-dual-plugin/goal-dual-plugin/` という入れ子コピーが作られます。

## 使い方

Claude Code セッション内で:

```
/goal-dual ユーザー認証機能を追加する。JWT でアクセストークンを発行し、/api/me エンドポイントを保護する。
```

ゴールをうまく書けない場合:

```
/goal-dual-plan ログイン後にユーザー情報を表示できるようにしたい
/goal-dual
```

`/goal-dual-plan` は `.goal-dual/plan/` を作るだけで、コードは変更しません。
`/goal-dual` を引数なしで実行すると、ready な plan がある場合だけ実装を開始します。
plan がない場合はエラーになります。

現在の変更をコードレビューするだけ（実装しない）:

```
/goal-dual-review
```

過去の実行履歴を確認する:

```
/goal-dual-history
```

ルーティングのみ実行する（実装しない）:

```
/goal-dual-route ユーザー認証機能を追加する
```

### 環境変数

| 変数名 | 説明 | デフォルト |
|---|---|---|
| `GOAL_DUAL_REVIEW_LEVEL` | コードレビューの厳格度（`strict`/`standard`/`relaxed`） | `standard` |
| `GOAL_DUAL_STAGNATION_THRESHOLD` | 同じ verdict が N 回続いたら STOP する閾値 | `3` |
| `GOAL_DUAL_WIP_COMMITS` | 未完了 iteration の WIP commit を作るか（`1`/`0`） | `1` |

## アンインストール

```bash
rm ~/.claude/commands/goal-dual.md
rm ~/.claude/commands/goal-dual-plan.md
rm ~/.claude/commands/goal-dual-history.md
rm ~/.claude/agents/goal-dual-*.md
rm -rf ~/.claude/goal-dual/
```

## ファイル構成

```
goal-dual-plugin/
├── .claude-plugin/
│   └── marketplace.json         # マーケットプレイス定義
├── plugins/
│   └── goal-dual/
│       ├── .claude-plugin/
│       │   └── plugin.json      # プラグインメタデータ
│       ├── commands/
│       │   ├── goal-dual.md              # /goal-dual スラッシュコマンド
│       │   ├── goal-dual-plan.md         # /goal-dual-plan スラッシュコマンド
│       │   ├── goal-dual-history.md      # /goal-dual-history スラッシュコマンド
│       │   └── goal-dual-review.md       # /goal-dual-review スラッシュコマンド
│       ├── agents/              # サブエージェント定義
│       └── scripts/             # Shell スクリプト群
├── install.sh                   # 手動インストールスクリプト
├── package.json
└── README.md
```

## ライセンス

MIT
