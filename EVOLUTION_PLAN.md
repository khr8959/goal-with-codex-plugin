# goal-dual 進化計画

この文書は、`goal-dual` の独自性を保ちながら、開発環境や個人利用でより便利にするための実装計画です。

`goal-dual` の中核価値は、単なる自動実装ではなく、Claude と Codex に役割分担させて「計画、実装、検証、レビュー」を反復することです。今後の拡張でも、この合議制と stateful な反復ループは維持します。

## 基本方針

- 非エンジニアでも安心して使える説明と停止理由を出す
- AI が勝手に大きく壊さないように、変更範囲と完了条件を明確にする
- Claude と Codex の合議評価を、人間に読めるレポートへ変換する
- 大きなゴールを小さく分けて、1 つずつ検証しながら進める
- 通常 while ループを安定基盤とし、Agent Teams は実験的機能として扱う

## 実装順序

1. 完了条件の自動整理
2. 変更範囲の制限
3. 人間向け完了レポート
4. タスク分割
5. review-only モード
6. プロジェクト記憶
7. PR 説明文生成

---

## 1. 完了条件の自動整理

### 目的

曖昧なゴールをそのまま実装に流さず、最初に「何を満たせば完了か」を明文化する。

例:

```text
/goal-dual ダッシュボードを使いやすくして
```

から、以下のような完了条件を生成する。

```md
## 完了条件

- 主要な数値が一目で確認できる
- 既存のデータ取得処理を壊さない
- モバイル表示でレイアウトが崩れない
- 自動テストまたは目視確認項目が残っている
```

### 変更対象

- `plugins/goal-dual/commands/goal-dual.md`
- `plugins/goal-dual/scripts/init.sh`
- 必要なら新規スクリプト: `plugins/goal-dual/scripts/acceptance-criteria.sh`

### 実装計画

1. `init.sh` で `.goal-dual/state/acceptance-criteria.md` を作れるようにする。
2. `/goal-dual` の Phase 0 後、Plan の前に「完了条件整理」ステップを追加する。
3. Claude にゴール本文から完了条件を Markdown で生成させる。
4. 生成した完了条件を `.goal-dual/state/acceptance-criteria.md` に保存する。
5. Plan、Claude evaluator、Codex evaluator の入力に `acceptance-criteria.md` を含める。
6. evaluator の判定基準を「ゴール本文」だけでなく「完了条件」を優先するように更新する。

### 完了条件

- `.goal-dual/state/acceptance-criteria.md` が毎回生成される
- Plan prompt に完了条件が含まれる
- Claude evaluator と Codex evaluator が完了条件を参照する
- eval が成功していても完了条件を満たさない場合は `incomplete` になる

### 注意点

- 非エンジニア向けに、完了条件は専門用語を避ける
- 完了条件が過剰に増えすぎないように 3 から 7 個程度に制限する
- ユーザーが明示した条件は削らない

---

## 2. 変更範囲の制限

### 目的

AI が関係ないファイルまで変更する不安を減らす。ユーザーが「触ってよい範囲」と「触ってはいけない範囲」を指定できるようにする。

例:

```text
/goal-dual ログイン画面だけ変更して。API とデータベースは触らないで。
```

### 変更対象

- `plugins/goal-dual/commands/goal-dual.md`
- `plugins/goal-dual/scripts/init.sh`
- `plugins/goal-dual/scripts/implement.sh`
- `plugins/goal-dual/scripts/commit-iter.sh`
- `plugins/goal-dual/agents/goal-dual-code-reviewer.md`

### 実装計画

1. `state.json` に以下のキーを追加する。

```json
{
  "scope_allow": [],
  "scope_deny": [],
  "scope_mode": "advisory"
}
```

2. 初期実装ではフラグパースを避け、ゴール本文から Claude が scope 案を抽出する。
3. `.goal-dual/state/scope.md` を生成し、以下を保存する。

```md
## 触ってよい範囲

- src/components/LoginForm.tsx

## 触ってはいけない範囲

- database
- API 認証ロジック
```

4. Plan prompt と Implement prompt に scope を含める。
5. `implement.sh` の Codex prompt に「scope 外変更は避ける」制約を追加する。
6. 実装後に `git diff --name-only` を見て、deny に該当する変更があれば warning を `.goal-dual/progress.txt` に記録する。
7. 最終レビューで scope 違反を Critical または Warning として扱う。

### 完了条件

- `.goal-dual/state/scope.md` が生成される
- Plan と Implement が scope を参照する
- scope 外の変更が検出された場合、progress と final-review に記録される
- `scope_mode` が `advisory` の場合は警告のみ、将来 `strict` を追加できる構造になっている

### 注意点

- 最初から厳密ブロックにしない。必要な関連ファイル変更まで止めると使いにくくなる
- 非エンジニア向けには「変更してよい場所」「変更しない場所」と表示する

---

## 3. 人間向け完了レポート

### 目的

非エンジニアでも結果を理解できるように、完了時または停止時に「何をしたか」「何が確認済みか」「人間が見るべき点」をまとめる。

### 変更対象

- 新規スクリプト: `plugins/goal-dual/scripts/final-report.sh`
- `plugins/goal-dual/commands/goal-dual.md`
- `plugins/goal-dual/scripts/archive.sh`

### 実装計画

1. `final-report.sh` を追加する。
2. 以下の入力を集める。

- `.goal-dual/goal.md`
- `.goal-dual/state/acceptance-criteria.md`
- `.goal-dual/state/evaluations/synthesized-<ITER>.json`
- `.goal-dual/state/final-review.md`
- `.goal-dual/state/eval-output.log`
- `git diff --stat <base>...HEAD`

3. `.goal-dual/state/final-report.md` を生成する。
4. report の構成は固定する。

```md
# goal-dual 完了レポート

## ゴール

## 実装したこと

## 確認結果

## 残っている注意点

## 人間が確認するとよいこと

## 次にやるとよいこと
```

5. `COMPLETE` 時だけでなく、`STOP_HUMAN` と `STOP_STAGNANT` でも停止レポートを出す。
6. final summary で `final-report.md` の場所を表示する。

### 完了条件

- 完了時に `.goal-dual/state/final-report.md` が生成される
- 停止時にも停止理由つきの report が生成される
- report が専門用語だけにならず、人間向けの説明を含む
- archive 後も report が履歴に残る

### 注意点

- 長すぎるレポートにしない
- テストログ全文を貼らず、要点だけを要約する

---

## 4. タスク分割

### 目的

大きすぎるゴールを小さな実装単位へ分割し、失敗や暴走を減らす。

例:

```text
/goal-dual 管理画面を作って
```

を以下のように分ける。

```md
1. データ構造と既存ルーティングを確認する
2. 一覧画面だけ作る
3. 詳細画面を作る
4. 編集機能を追加する
5. 権限チェックを入れる
```

### 変更対象

- `plugins/goal-dual/commands/goal-dual.md`
- `plugins/goal-dual/scripts/init.sh`
- 新規スクリプト候補: `plugins/goal-dual/scripts/decompose-goal.sh`

### 実装計画

1. `.goal-dual/state/task-breakdown.md` を作るステップを追加する。
2. ゴールが大きい場合、Claude が 2 から 6 個の小タスクに分割する。
3. `state.json` に以下を追加する。

```json
{
  "task_breakdown_enabled": true,
  "current_task_index": 0,
  "task_count": 0
}
```

4. Plan prompt に「現在の小タスク」を含める。
5. evaluator は全体ゴールではなく、現在の小タスクの完了をまず判定する。
6. 小タスクが完了したら `current_task_index` を進める。
7. 全小タスクが完了したら、全体ゴールの最終評価へ進む。

### 完了条件

- 大きなゴールに対して `.goal-dual/state/task-breakdown.md` が生成される
- 各 iteration が現在の小タスクを参照する
- 小タスク完了後に次の小タスクへ進む
- 全小タスク完了後に最終合議評価が走る

### 注意点

- 最初は常時有効にせず、ゴールが大きい場合だけ使う
- 小さな修正では分割しない
- 小タスク完了と全体完了を混同しない

---

## 5. review-only モード

### 目的

実装まで任せるのが怖いユーザー向けに、既存の変更を Claude + Codex 合議でレビューするだけの入口を作る。

例:

```text
/goal-dual-review 今の変更が安全か確認して
```

または将来的に:

```text
/goal-dual --review-only 今の変更を確認して
```

### 変更対象

- 新規コマンド: `plugins/goal-dual/commands/goal-dual-review.md`
- 既存エージェント: `plugins/goal-dual/agents/goal-dual-code-reviewer.md`
- 必要なら新規スクリプト: `plugins/goal-dual/scripts/review-only.sh`
- `install.sh`
- `README.md`

### 実装計画

1. `/goal-dual-review` コマンドを追加する。
2. `init.sh` を使わず、既存の作業ツリー差分を対象にする。
3. `.goal-dual-review/` または `.goal-dual/state/review-only-*` に一時結果を保存する。
4. Claude evaluator と Codex review を使って、以下を判定する。

- 重大な問題があるか
- 要件に対して不足があるか
- テストが必要か
- commit してよい状態か

5. 結果を `review-report.md` に保存する。
6. 実装や git commit は行わない。

### 完了条件

- `/goal-dual-review` が使える
- 既存差分をレビューできる
- コード修正や commit をしない
- Claude と Codex の両方の観点を含む report が生成される

### 注意点

- review-only は安全な入口なので、絶対に実装を変更しない
- dirty check で止めず、dirty 状態をレビュー対象として扱う

---

## 6. プロジェクト記憶

### 目的

同じプロジェクトで繰り返し使う注意点を蓄積し、毎回 Plan と Implement に反映する。

例:

```md
# goal-dual Project Memory

- テストは npm test ではなく npm run test:unit を使う
- src/generated は編集禁止
- API を変更した場合は openapi.yaml も更新する
- console.log は lint で落ちる
```

### 変更対象

- `plugins/goal-dual/scripts/init.sh`
- `plugins/goal-dual/commands/goal-dual.md`
- `plugins/goal-dual/scripts/implement.sh`
- 新規スクリプト候補: `plugins/goal-dual/scripts/update-project-memory.sh`

### 実装計画

1. プロジェクト直下に `.goal-dual-memory.md` をサポートする。
2. `init.sh` で `.goal-dual-memory.md` があれば state にパスを保存する。
3. Plan prompt と Implement prompt に memory の内容を含める。
4. STOP_STAGNANT や STOP_HUMAN 時に「記憶へ追加すべき教訓」を `memory-suggestions.md` に出す。
5. 自動で memory を編集するのは後回しにし、最初は提案だけにする。

### 完了条件

- `.goal-dual-memory.md` がある場合、Plan と Implement が参照する
- 停止時に `.goal-dual/state/memory-suggestions.md` が生成される
- memory がない場合も通常通り動く

### 注意点

- memory は強い制約として扱いすぎない。古い情報が残る可能性がある
- 自動追記は誤学習のリスクがあるため、初期実装では提案に留める

---

## 7. PR 説明文生成

### 目的

完了後に GitHub PR や changelog に使える説明文を自動生成する。

### 変更対象

- 新規スクリプト: `plugins/goal-dual/scripts/generate-pr-description.sh`
- `plugins/goal-dual/commands/goal-dual.md`
- `README.md`

### 実装計画

1. COMPLETE 時に `.goal-dual/state/pr-description.md` を生成する。
2. 入力として以下を使う。

- ゴール
- 完了条件
- synthesized evaluation
- final review
- git diff stat
- commit history

3. 出力形式を固定する。

```md
## Summary

- 

## Test

- 

## Review Notes

- 

## Human Check

- 
```

4. 最終サマリに `pr-description.md` のパスを表示する。
5. 将来的に `gh pr create --body-file` と連携できる構造にする。

### 完了条件

- COMPLETE 時に `.goal-dual/state/pr-description.md` が生成される
- `Summary`, `Test`, `Review Notes`, `Human Check` が含まれる
- GitHub PR に貼れる粒度になっている

### 注意点

- 実際の `gh pr create` 実行は最初はしない
- 人間が確認すべき項目を必ず残す

---

## 先に直すべき基盤課題

機能追加の前に、以下の基盤課題を先に直すと後続実装が安定する。

### A. `CLAUDE_PLUGIN_ROOT` の責務分離

現状、`CLAUDE_PLUGIN_ROOT` が `codex@openai-codex` の root として使われている一方で、goal-dual 自身の script root としても扱われている箇所がある。

#### 実装計画

1. `CODEX_PLUGIN_ROOT` を導入する。
2. `GOAL_DUAL_PLUGIN_ROOT` を導入する。
3. `resolve-plugin-root.sh` を `resolve-codex-plugin-root.sh` 相当に整理する。
4. `teammate-idle-hook.sh` は `GOAL_DUAL_PLUGIN_ROOT` からコピーする。
5. `state.json` に両方の root を保存する。

#### 完了条件

- Codex companion の参照先と goal-dual scripts の参照先が分離されている
- Agent Teams hook コピーが正しい場所から行われる

### B. archive 後に dirty を残さない

現状、完了後に `.goal-dual/` を commit してから archive するため、`.goal-dual/` の削除や `.gitignore` 変更が未コミットで残る可能性がある。

#### 実装計画

1. `.goal-dual/` を原則として実行状態ディレクトリにする。
2. `commit-iter.sh` で `.goal-dual/` を commit するかどうかを設計し直す。
3. 推奨方針は、実装成果物だけ commit し、`.goal-dual/` と `.goal-dual-archive/` は ignore する。
4. 履歴は archive と final report に残す。

#### 完了条件

- COMPLETE 後に作業ツリーへ不要な dirty が残らない
- `.goal-dual/` の扱いが README に明記されている

---

## Claude Code への実装依頼テンプレート

各項目を実装するときは、Claude Code に以下の形式で依頼する。

```text
EVOLUTION_PLAN.md の「<項目名>」だけを実装してください。

制約:
- 他の項目は実装しない
- 既存の通常 while ループを壊さない
- Agent Teams は必要最小限の追従に留める
- README に必要な使い方を追記する
- 実装後に shellcheck 相当の静的確認、または最低限 bash -n を実行する

完了条件:
- EVOLUTION_PLAN.md の該当項目の「完了条件」を満たす
- 変更内容を短く説明する
```

