# goal-dual プラグイン

Claude + Codex の合議制で、単一の自然言語ゴールを達成まで継続実装する Claude Code プラグインです。

## 概要

`/goal-dual <ゴール>` と入力するだけで、以下のループを自律的に実行します:

```
Plan（Explore 統合済み・公式 Plan エージェント） → 批判的レビュー（Codex）
→ Implement（実装、Codex 委譲） → eval-cmd 実行
→ 合議評価（Claude + Codex 並列） → コードレビュー（Codex + Sonnet 判定）
→ 達成 or 次イテレーション
```

## 要件

- Claude Code（最新版）
- Node.js 18 以上
- `jq`
- `git`
- [codex CLI](https://github.com/openai/codex): `npm install -g @openai/codex`
- Claude Code の `codex@openai-codex` プラグイン（Claude Code 内で `/install codex@openai-codex`）

## インストール方法

```bash
git clone https://github.com/khr8959/goal-dual-plugin.git
cd goal-dual-plugin
bash install.sh
```

これで以下がインストールされます:

- `~/.claude/commands/goal-dual.md`（`/goal-dual` スラッシュコマンド）
- `~/.claude/commands/goal-dual-history.md`（`/goal-dual-history` スラッシュコマンド）
- `~/.claude/commands/goal-dual-review.md`（`/goal-dual-review` スラッシュコマンド）
- `~/.claude/agents/goal-dual-*.md`（サブエージェント定義 × 7）
- `~/.claude/goal-dual/scripts/*.sh`（実行スクリプト × 21）

## 使い方

Claude Code セッション内で:

```
/goal-dual ユーザー認証機能を追加する。JWT でアクセストークンを発行し、/api/me エンドポイントを保護する。
```

現在の変更をコードレビューするだけ（実装しない）:

```
/goal-dual-review
```

過去の実行履歴を確認する:

```
/goal-dual-history
```

### 環境変数

| 変数名 | 説明 | デフォルト |
|---|---|---|
| `GOAL_DUAL_REVIEW_LEVEL` | コードレビューの厳格度（`strict`/`standard`/`relaxed`） | `standard` |
| `GOAL_DUAL_STAGNATION_THRESHOLD` | 同じ verdict が N 回続いたら STOP する閾値 | `3` |
| `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` | `1` で Agent Teams モードを有効化（**実験的**） | 未設定 |

## ワークフロー詳細

```
Phase 0: 初期化 (init.sh)
  - git / no-git 自動検出
  - main/master なら自動でブランチ作成
  - eval-cmd 自動検出（npm test / pytest）
  - .git/info/exclude に .goal-dual/ と .goal-dual-archive/ を追記（git status に影響しない）
  - .goal-dual/ ディレクトリ生成
  - .goal-dual-memory.md の自動検出（プロジェクト記憶）

Phase 0.5: 受け入れ条件の整理 (acceptance-criteria.sh)
  - ゴールから 3〜7 個の受け入れ条件を生成 → acceptance-criteria.md

Phase 0.7: 変更範囲の整理
  - ゴールから scope.md（変更可否パターン）を生成 → state.json に保存

Phase 0.8: タスク分割 (decompose-goal.sh)
  - 大きなゴールの場合のみ 2〜6 タスクに分割 → task-breakdown.md

メインループ（安定版）:
  Step 0: dirty check（.goal-dual/ と .goal-dual-archive/ 外の未コミット変更検出）
  Step 1: iteration 番号インクリメント
  Step 2: Plan（公式 Plan エージェントが Explore も内包）+ mini-plan.md 保存
  Step 3: Adversarial Review（Codex で計画批判）→ plan-revised.md
  Step 4: Implement（Codex 委譲・プロジェクト記憶・スコープ制約を反映）
  Step 5: eval-cmd 実行（npm test / pytest / 任意コマンド）
  Step 6: 合議評価（Claude evaluator + Codex evaluator 並列・受け入れ条件優先）
  Step 7: Safety check（STAGNANT / STOP_HUMAN 検出）
  Step 8: 判定処理
    - complete → Code Review（Codex + Sonnet 判定）→ pass: コミット & 完了
    - incomplete → wip コミット → ループ先頭へ
    - regressed → 変更リセット検討 → ループ先頭へ

終了処理:
  - final-report.sh: 人間向け最終レポート生成
  - update-project-memory.sh: 停止時に教訓を提案（STOP_STAGNANT / STOP_HUMAN）
  - generate-pr-description.sh: PR 説明文生成 + 完了情報を state.json に保存（COMPLETE 時）
  - archive.sh: .goal-dual/ を .goal-dual-archive/ へ移動（COMPLETE 時）

終了: COMPLETE / STOP_HUMAN / STOP_STAGNANT / STOP_DIRTY
```

### COMPLETE 時に state.json へ保存される完了情報

COMPLETE で終了した場合、`generate-pr-description.sh` が以下のフィールドを
`state.json` に追記します（archive 後も `.goal-dual-archive/<ts>-<slug>/state.json` で参照可能）:

| フィールド | 内容 |
|---|---|
| `completed_at` | 完了時刻（ISO8601・UTC）|
| `pr_description_path` | PR 説明文の相対パス（`state/pr-description.md`）|
| `final_review_path` | 最終レビューの相対パス（`state/final-review.md`。無い場合は未設定）|
| `review_passed` | 最終レビューを通過したか（`true` / `false`）|
| `review_result` | レビュー結果の要約（例: `pass: コードレビュー完了`）|

パスは `.goal-dual/` ルートからの相対表記で保存されるため、アーカイブへ移動した後も
そのまま辿れます。

### .goal-dual/ と .goal-dual-archive/ について

- `.goal-dual/` — 実行中のステートディレクトリ（gitignore 対象。実行ログ・評価 JSON・計画ファイルを保持）
- `.goal-dual-archive/` — COMPLETE 後に `.goal-dual/` を移動したアーカイブ（gitignore 対象）

どちらも Git のコミット対象ではありません。実装成果物のみがコミットされます。

## サブエージェント一覧

| ファイル | 役割 | モデル |
|---|---|---|
| `goal-dual-adversarial-reviewer.md` | mini-plan を Codex で批判的レビュー → plan-revised.md | Haiku |
| `goal-dual-implementer.md` | plan-revised.md を元に実装（Codex 委譲のみ） | Haiku |
| `goal-dual-claude-evaluator.md` | ゴール達成判定（Claude 側）| Sonnet |
| `goal-dual-codex-evaluator.md` | ゴール達成判定（Codex 側）| Haiku |
| `goal-dual-code-reviewer.md` | 最終コードレビュー（Codex + Sonnet 自前判定）| Sonnet |
| `goal-dual-implementer-team.md` | implementer の Teams モード版（実験的・永続メンバー）| Haiku |
| `goal-dual-claude-evaluator-team.md` | claude-evaluator の Teams モード版（実験的・永続メンバー）| Sonnet |

## スクリプト一覧

| ファイル | 役割 |
|---|---|
| `init.sh` | 初期化（ディレクトリ作成・state.json 生成・.git/info/exclude 更新）|
| `dirty-check.sh` | 未コミット変更検出（.goal-dual/ と .goal-dual-archive/ を除外）|
| `run-eval.sh` | eval-cmd 実行・結果保存 |
| `safety.sh` | 停滞・強制停止の検出 |
| `commit-iter.sh` | 実装ファイルのみをコミット（スコープ違反を advisory チェック）|
| `archive.sh` | COMPLETE 後に .goal-dual/ を .goal-dual-archive/ へ移動 |
| `adversarial-review.sh` | Codex で計画を批判的レビュー |
| `implement.sh` | Codex に実装を委譲（プロジェクト記憶・スコープ制約を反映）|
| `codex-evaluate.sh` | Codex でゴール達成を判定（受け入れ条件・現在タスクを考慮）|
| `collect-eval-inputs.sh` | 評価エージェントの入力情報を収集 |
| `acceptance-criteria.sh` | ゴールから受け入れ条件を生成 → acceptance-criteria.md |
| `decompose-goal.sh` | ゴールを小タスクに分割 → task-breakdown.md |
| `final-report.sh` | 完了・停止時の人間向けレポートを生成 |
| `generate-pr-description.sh` | COMPLETE 時に GitHub PR 説明文を生成 |
| `update-project-memory.sh` | 停止時に教訓を提案 → memory-suggestions.md |
| `review-only.sh` | 現在の変更をレビューのみ（/goal-dual-review から呼び出し）|
| `list-history.sh` | .goal-dual-archive/ の履歴一覧を表示 |
| `lib.sh` | 共通ユーティリティ（resolve 関数・state_set/get など）|
| `resolve-codex-plugin-root.sh` | CODEX_PLUGIN_ROOT を解決・export |
| `resolve-plugin-root.sh` | 後方互換 shim（CODEX_PLUGIN_ROOT を export）|
| `teammate-idle-hook.sh` | Agent Teams の TeammateIdle フック（実験的）|

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
│       │   ├── goal-dual-history.md      # /goal-dual-history スラッシュコマンド
│       │   └── goal-dual-review.md       # /goal-dual-review スラッシュコマンド
│       ├── agents/              # サブエージェント定義
│       │   ├── goal-dual-adversarial-reviewer.md
│       │   ├── goal-dual-implementer.md
│       │   ├── goal-dual-implementer-team.md       # Agent Teams 版（実験的）
│       │   ├── goal-dual-claude-evaluator.md
│       │   ├── goal-dual-claude-evaluator-team.md  # Agent Teams 版（実験的）
│       │   ├── goal-dual-codex-evaluator.md
│       │   └── goal-dual-code-reviewer.md
│       └── scripts/             # Shell スクリプト群
│           ├── init.sh
│           ├── dirty-check.sh
│           ├── run-eval.sh
│           ├── safety.sh
│           ├── commit-iter.sh
│           ├── archive.sh
│           ├── adversarial-review.sh
│           ├── implement.sh
│           ├── codex-evaluate.sh
│           ├── collect-eval-inputs.sh
│           ├── acceptance-criteria.sh
│           ├── decompose-goal.sh
│           ├── final-report.sh
│           ├── generate-pr-description.sh
│           ├── update-project-memory.sh
│           ├── review-only.sh
│           ├── list-history.sh
│           ├── lib.sh
│           ├── resolve-codex-plugin-root.sh
│           ├── resolve-plugin-root.sh   # 後方互換 shim
│           └── teammate-idle-hook.sh    # Agent Teams 用（実験的）
├── install.sh                   # 手動インストールスクリプト
├── package.json
└── README.md
```

## Agent Teams モード（実験的）

> **通常利用には不要です。** 標準の while ループモードが安定版です。

`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` を設定して起動すると、implementer と
claude-evaluator を永続メンバーとして Agent Teams API で動作します。

Claude Code 側の Agent Teams API は変更が入る可能性があり、動作が不安定になる場合があります。
API の起動が失敗した場合は自動的に while ループへフォールバックします。
応答遅延や不明確な応答ではフォールバックしません。

Teams モードを利用する場合は、TeammateIdle フックの設定が推奨されます。
詳細は `/goal-dual` 実行時に表示される案内を参照してください。

### 有効になっているか確認する方法

`/goal-dual` 実行時、`init.sh` の出力に `agent-teams : 有効（実験的）` と表示され、
有効な場合は警告バナーが出ます。シェルから直接確認するには:

```bash
echo "$CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS"
# 1 と表示されれば有効、空なら無効
```

### 無効化する方法（安定版に戻す）

Agent Teams モードは環境変数で切り替わります。無効化するには Claude Code を終了し、
起動したシェルで次を実行してから Claude Code を再起動してください:

```bash
unset CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS
```

`~/.zshrc` / `~/.bashrc` などに `export CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` を
書いている場合は、その行を削除（またはコメントアウト）してからシェルを開き直してください。
無効化すると、ほとんどのユーザー向けの安定版 while ループモードで動作します。

## アンインストール

```bash
rm ~/.claude/commands/goal-dual.md
rm ~/.claude/commands/goal-dual-history.md
rm ~/.claude/agents/goal-dual-*.md
rm -rf ~/.claude/goal-dual/
```

## ライセンス

MIT
