# goal-dual 基盤修正計画

この文書は、機能追加の前に直しておきたい設計上の気になる点を、Claude Code で 1 つずつ実装できるように整理したものです。

対象は以下の 4 点です。

1. archive 後に dirty を残す可能性
2. `CLAUDE_PLUGIN_ROOT` の責務混線
3. README と実体のズレ
4. Agent Teams モードの不安定さと通常モードへの影響

## 実装順序

1. `CLAUDE_PLUGIN_ROOT` の責務分離
2. archive 後に dirty を残さない設計
3. README と実体の同期
4. Agent Teams モードの隔離と注意書き強化

この順序にする理由は、1 と 2 が実行時バグに直結し、3 と 4 は配布品質と保守性の改善だからです。

---

## 1. `CLAUDE_PLUGIN_ROOT` の責務分離

### 現状の問題

現在、`CLAUDE_PLUGIN_ROOT` が主に `codex@openai-codex` プラグインの root として使われています。

一方で、Agent Teams 用の `teammate-idle-hook.sh` コピー処理では、goal-dual 自身の script root として扱われています。

該当箇所:

- `plugins/goal-dual/scripts/init.sh`
- `plugins/goal-dual/scripts/lib.sh`
- `plugins/goal-dual/scripts/resolve-plugin-root.sh`
- `plugins/goal-dual/scripts/implement.sh`
- `plugins/goal-dual/scripts/adversarial-review.sh`
- `plugins/goal-dual/scripts/codex-evaluate.sh`
- `plugins/goal-dual/agents/goal-dual-code-reviewer.md`
- `plugins/goal-dual/agents/goal-dual-implementer-team.md`

このままだと、`codex-companion.mjs` の場所と `goal-dual` 自身の script の場所が混ざり、Teams hook のコピーが期待通り動かない可能性があります。

### 目標

Codex プラグインの root と、goal-dual 自身の root を明確に分ける。

### 設計案

以下の 2 つの概念を導入する。

```text
CODEX_PLUGIN_ROOT
  codex@openai-codex プラグインの root
  scripts/codex-companion.mjs を持つ

GOAL_DUAL_PLUGIN_ROOT
  goal-dual プラグイン自身の root
  commands/, agents/, scripts/ を持つ
```

`state.json` には以下を保存する。

```json
{
  "codex_plugin_root": "...",
  "goal_dual_plugin_root": "..."
}
```

既存の `plugin_root` は後方互換用に一時的に残してもよいが、新規コードでは使わない。

### 実装計画

1. `lib.sh` に `resolve_codex_plugin_root()` を追加する。
2. `lib.sh` に `resolve_goal_dual_plugin_root()` を追加する。
3. 既存の `resolve_plugin_root()` は互換 shim とし、内部では `resolve_codex_plugin_root()` を呼ぶ。
4. `init.sh` で以下を解決して state に保存する。

```bash
CODEX_PLUGIN_ROOT=$(resolve_codex_plugin_root)
GOAL_DUAL_PLUGIN_ROOT=$(resolve_goal_dual_plugin_root)
```

5. `codex-companion.mjs` を使うスクリプトは `CODEX_PLUGIN_ROOT` を参照する。
6. `teammate-idle-hook.sh` のコピー処理は `GOAL_DUAL_PLUGIN_ROOT` を参照する。
7. `resolve-plugin-root.sh` は名前が紛らわしいため、可能なら `resolve-codex-plugin-root.sh` を追加し、既存ファイルは互換用 shim にする。
8. エージェント定義内の `CLAUDE_PLUGIN_ROOT` 表記を `CODEX_PLUGIN_ROOT` に置き換える。

### 完了条件

- `codex-companion.mjs` は `CODEX_PLUGIN_ROOT` から参照される
- `teammate-idle-hook.sh` は `GOAL_DUAL_PLUGIN_ROOT` からコピーされる
- `state.json` に `codex_plugin_root` と `goal_dual_plugin_root` が保存される
- 既存の通常 while ループが動作する
- `bash -n plugins/goal-dual/scripts/*.sh` が通る

### 注意点

- Claude Code 側が自動で設定する `CLAUDE_PLUGIN_ROOT` がある場合、意味を上書きしない
- 既存ユーザーの state が `plugin_root` しか持っていない場合でも再開できるようにする

---

## 2. archive 後に dirty を残さない設計

### 現状の問題

現在の流れでは、`complete` 判定後に `commit-iter.sh pass` が呼ばれ、その後に `archive.sh` が呼ばれます。

問題は、`commit-iter.sh` が `.goal-dual/` の一部を commit した後、`archive.sh` が `.goal-dual/` を `.goal-dual-archive/` に移動する点です。

結果として、以下が未コミット変更として残る可能性があります。

- `.goal-dual/` 配下の tracked file 削除
- `.gitignore` への `.goal-dual-archive/` 追記
- archive ディレクトリの生成

### 目標

`COMPLETE` 後に不要な dirty を残さない。

### 推奨設計

`.goal-dual/` は実行状態ディレクトリとして扱い、原則 commit しない。

実装成果物だけを commit 対象にし、履歴やレポートは `.goal-dual-archive/` に保存する。

`.goal-dual/` と `.goal-dual-archive/` は `.gitignore` に入れる。

### 変更対象

- `plugins/goal-dual/scripts/init.sh`
- `plugins/goal-dual/scripts/commit-iter.sh`
- `plugins/goal-dual/scripts/archive.sh`
- `plugins/goal-dual/scripts/dirty-check.sh`
- `plugins/goal-dual/scripts/lib.sh`
- `README.md`

### 実装計画

1. `init.sh` の `.goal-dual/.gitignore` 生成だけでなく、プロジェクト直下 `.gitignore` に以下を追加する処理を検討する。

```gitignore
.goal-dual/
.goal-dual-archive/
```

2. ただし、既存プロジェクトの `.gitignore` を勝手に変更するのは副作用があるため、最初は以下のどちらかを選ぶ。

- 方針 A: 自動で `.gitignore` に追記する
- 方針 B: `.goal-dual/` は `git add -f` しないだけにして、`.gitignore` 追記はユーザーへ案内する

推奨は方針 A。ただし追記は重複チェック付きにする。

3. `commit-iter.sh` から `.goal-dual/progress.txt`, `.goal-dual/goal.md`, `.goal-dual/state.json`, `synthesized-*.json`, `final-review.md` の `git add` を削除する。
4. `commit-iter.sh` は実装ファイルだけを stage する。
5. `archive.sh` は `.goal-dual/` を移動しても tracked file 削除が出ない状態にする。
6. `archive.sh` が `.gitignore` を変更する場合、その変更をどう扱うか明確にする。
7. `dirty-check.sh` は `.goal-dual/` と `.goal-dual-archive/` を dirty 判定から除外する。
8. README に「`.goal-dual/` は実行ログであり commit 対象ではない」と明記する。

### 完了条件

- `commit-iter.sh pass` 後に実装成果物だけが commit される
- `archive.sh` 実行後に `.goal-dual/` の削除差分が出ない
- `.goal-dual-archive/` が dirty 判定に引っかからない
- README に `.goal-dual/` と `.goal-dual-archive/` の扱いが書かれている
- `bash -n plugins/goal-dual/scripts/*.sh` が通る

### 注意点

- `.goal-dual/` を commit しなくなると、実行履歴は Git 履歴ではなく archive に残る
- 以前の設計と変わるため、README の説明は必ず更新する
- 既存の tracked `.goal-dual/` があるプロジェクトでの移行は別途案内が必要

---

## 3. README と実体の同期

### 現状の問題

README の記述が現在のファイル構成とずれています。

例:

- scripts が 8 個と書かれているが、実体はそれより多い
- `/goal-dual-history` の説明が薄い
- `Agent Teams` の実験的扱いが実装の複雑さに比べて軽い
- `.goal-dual/` と `.goal-dual-archive/` の扱いが明確ではない
- `install.sh` による手動インストールと plugin metadata の関係がわかりにくい

### 目標

README を、現在の設計と実装に一致させる。

### 変更対象

- `README.md`
- 必要なら `package.json`
- 必要なら `.claude-plugin/marketplace.json`
- 必要なら `plugins/goal-dual/.claude-plugin/plugin.json`

### 実装計画

1. `rg --files` で実際のファイル構成を確認する。
2. README のファイル構成ツリーを実体に合わせる。
3. インストール後に配置されるコマンドを明記する。

```text
/goal-dual
/goal-dual-history
```

4. scripts 一覧を更新する。
5. agents 一覧を更新する。
6. `.goal-dual/` と `.goal-dual-archive/` の用途を説明する。
7. `Agent Teams` は実験的機能として明確に分ける。
8. 必要な依存関係を再確認する。

```text
Claude Code
Node.js 18+
jq
git
codex CLI
codex@openai-codex Claude Code plugin
```

9. `install.sh` と Claude Code plugin metadata の関係を説明する。
10. 「通常モードが安定版、Agent Teams は実験的」と書く。

### 完了条件

- README の scripts 数が実体と一致する
- `/goal-dual-history` の説明がある
- `.goal-dual/` と `.goal-dual-archive/` の扱いがわかる
- Agent Teams の注意点が明記されている
- 初見ユーザーが install から実行まで迷わない

### 注意点

- README は長くしすぎない
- 詳細すぎる内部設計は別ドキュメントへ逃がしてよい
- 非エンジニアにもわかる言葉を使う

---

## 4. Agent Teams モードの隔離と注意書き強化

### 現状の問題

Agent Teams モードは、永続メンバー、phase 管理、SendMessage、TeammateIdle hook、shutdown など複雑な設計になっています。

一方で、Claude Code 側の Agent Teams API が変わると壊れやすく、通常 while ループにも影響が出る可能性があります。

### 目標

通常 while ループの安定性を守りながら、Agent Teams は明確に experimental として隔離する。

### 変更対象

- `plugins/goal-dual/commands/goal-dual.md`
- `plugins/goal-dual/scripts/init.sh`
- `plugins/goal-dual/scripts/teammate-idle-hook.sh`
- `plugins/goal-dual/agents/goal-dual-implementer-team.md`
- `plugins/goal-dual/agents/goal-dual-claude-evaluator-team.md`
- `README.md`

### 実装計画

1. `goal-dual.md` の冒頭に、通常モードと Agent Teams モードの分岐をより明確に書く。
2. 通常モードの手順と Agent Teams モードの手順を混ぜず、見出しを分ける。
3. `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` がない場合、Teams 関連処理を一切走らせないことを明記する。
4. `init.sh` の Teams hook コピー処理を、`GOAL_DUAL_PLUGIN_ROOT` 修正後の正しい root に合わせる。
5. Teams 起動失敗時のみ while ループへフォールバックする方針を維持する。
6. Teams 応答遅延や不明確な応答では、勝手にフォールバックしないことを再確認する。
7. README では Agent Teams を「実験的、通常利用では不要」と説明する。
8. 可能なら Teams 関連 state key を README または別文書にまとめる。

### 完了条件

- 通常モードだけ使う場合、Teams 関連の副作用がない
- Agent Teams の hook コピーが正しい root から行われる
- README で Agent Teams が experimental と明確に説明される
- `goal-dual.md` の通常モードと Teams モードが読み分けやすくなる
- `bash -n plugins/goal-dual/scripts/*.sh` が通る

### 注意点

- Agent Teams を削除する計画ではない
- ただし、通常モードの安定性を最優先する
- API 仕様が不安定な部分は、README で期待値を下げる

---

## Claude Code への実装依頼テンプレート

各項目を実装するときは、Claude Code に以下の形式で依頼する。

```text
FOUNDATION_FIX_PLAN.md の「<項目名>」だけを実装してください。

制約:
- 他の項目は実装しない
- 通常 while ループを壊さない
- 既存ユーザーの state 再開をできるだけ壊さない
- README が影響を受ける場合は同時に更新する
- 実装後に bash -n plugins/goal-dual/scripts/*.sh を実行する

完了条件:
- FOUNDATION_FIX_PLAN.md の該当項目の「完了条件」を満たす
- 変更内容と残課題を短く説明する
```

