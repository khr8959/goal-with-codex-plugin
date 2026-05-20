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

実験的に Agent Teams モード（永続メンバー駆動）をサポートしています。
`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` を設定して起動すると、implementer と
claude-evaluator を Teams の永続メンバーとして起動します（API 未対応時は
自動的に while ループへフォールバック）。

## 要件

- Claude Code（最新版）
- Node.js 18 以上
- jq
- [codex CLI](https://github.com/openai/codex): `npm install -g @openai/codex`
- Claude Code の `codex@openai-codex` プラグイン（Claude Code 内で `/install codex@openai-codex`）

## インストール方法

### 方法 A: install.sh を使う（推奨）

```bash
git clone https://github.com/khr8959/goal-dual-plugin.git
cd goal-dual-plugin
bash install.sh
```

これで以下がインストールされます:
- `~/.claude/commands/goal-dual.md`（スラッシュコマンド）
- `~/.claude/agents/goal-dual-*.md`（サブエージェント定義 × 7。Teams 版 2 つを含む）
- `~/.claude/goal-dual/scripts/*.sh`（実行スクリプト × 8）

### 方法 B: npm からインストール（将来対応予定）

```bash
# Claude Code が npm レジストリ連携に対応次第:
# /install goal-dual-plugin
```

現時点では Claude Code のプラグインマーケットプレイスは GitHub リポジトリ経由での配布が主流です。
`install.sh` を使った手動インストールが確実な方法です。

## 使い方

Claude Code セッション内で:

```
/goal-dual ユーザー認証機能を追加する。JWT でアクセストークンを発行し、/api/me エンドポイントを保護する。
```

### 環境変数

| 変数名 | 説明 | デフォルト |
|---|---|---|
| `GOAL_DUAL_REVIEW_LEVEL` | コードレビューの厳格度（`strict`/`standard`/`relaxed`） | `standard` |
| `GOAL_DUAL_STAGNATION_THRESHOLD` | 同じ verdict が N 回続いたら STOP する閾値 | `3` |
| `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` | `1` で Agent Teams モードを有効化（実験的） | 未設定 |

## ワークフロー詳細

```
Phase 0: 初期化 (init.sh)
  - git / no-git 自動検出
  - main/master なら自動でブランチ作成
  - eval-cmd 自動検出（npm test / pytest）
  - .goal-dual/ ディレクトリ生成

メインループ:
  Step 0: dirty check（.goal-dual/ 外の未コミット変更検出）
  Step 1: iteration 番号インクリメント
  Step 2: Plan（公式 Plan エージェントが Explore も内包）+ mini-plan.md 保存
  Step 3: Adversarial Review（Codex で計画批判）→ plan-revised.md
  Step 4: Implement（常に Codex 委譲）
  Step 5: eval-cmd 実行（npm test / pytest / 任意コマンド）
  Step 6: 合議評価（Claude evaluator + Codex evaluator 並列）
  Step 7: Safety check（STAGNANT / STOP_HUMAN 検出）
  Step 8: 判定処理
    - complete → Code Review（Codex + Sonnet 判定）→ pass: コミット & 完了
    - incomplete → wip コミット → ループ先頭へ
    - regressed → 変更リセット検討 → ループ先頭へ

終了: COMPLETE / STOP_HUMAN / STOP_STAGNANT / STOP_DIRTY
```

## サブエージェント一覧

| ファイル | 役割 | モデル |
|---|---|---|
| `goal-dual-adversarial-reviewer.md` | mini-plan を Codex で批判的レビュー → plan-revised.md | Haiku |
| `goal-dual-implementer.md` | plan-revised.md を元に実装（Codex 委譲のみ） | Haiku |
| `goal-dual-claude-evaluator.md` | ゴール達成判定（Claude 側）| Sonnet |
| `goal-dual-codex-evaluator.md` | ゴール達成判定（Codex 側）| Haiku |
| `goal-dual-code-reviewer.md` | 最終コードレビュー（Codex + Sonnet 自前判定）| Sonnet |
| `goal-dual-implementer-team.md` | implementer の Teams モード版（永続メンバー、実験的） | Haiku |
| `goal-dual-claude-evaluator-team.md` | claude-evaluator の Teams モード版（永続メンバー、実験的） | Sonnet |

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
│       │   └── goal-dual.md     # /goal-dual スラッシュコマンド本体
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
│           ├── collect-eval-inputs.sh   # 評価エージェントの入力収集を統合
│           ├── lib.sh
│           └── resolve-plugin-root.sh
├── install.sh                   # 手動インストールスクリプト
├── package.json
└── README.md
```

## アンインストール

```bash
rm ~/.claude/commands/goal-dual.md
rm ~/.claude/agents/goal-dual-*.md
rm -rf ~/.claude/goal-dual/
```

## ライセンス

MIT
