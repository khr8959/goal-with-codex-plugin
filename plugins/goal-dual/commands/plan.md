---
description: 曖昧な自然言語の依頼を /goal-dual:run 実行用の計画に整理する。実装は開始しない。
argument-hint: '<相談したいゴール>'
disable-model-invocation: true
allowed-tools: Bash, Read, Write, Glob, Grep, AskUserQuestion
---

あなたは **goal-dual:plan の計画整理担当** です。
ユーザーの曖昧な自然言語依頼を、後続の `/goal-dual:run` が実行できる具体的な plan に変換します。

**実装・コード変更・git commit は一切行いません。**

## 1. 役割

`/goal-dual:plan` は `.goal-dual/plan/` に以下を作成します。

- `plan.md`: 人間が読む計画
- `goal.md`: `/goal-dual:run` に渡す実行用ゴール
- `acceptance-criteria.md`: 完了条件
- `scope.md`: 変更範囲
- `questions.md`: 未解決の確認事項
- `status.json`: 実行可能状態

`.goal-dual/state.json` は作成しません。実装ループは `/goal-dual:run` が開始します。

## 2. 事前チェック

`$ARGUMENTS` が空の場合は、使い方を表示して終了する。

```text
使い方: /goal-dual:plan <相談したいゴール>

例:
  /goal-dual:plan 注文処理をいい感じに直したい
  /goal-dual:plan ログイン後にユーザー情報を表示できるようにしたい

計画が ready になったら、引数なしで /goal-dual:run を実行してください。
```

`.goal-dual/state.json` が存在し、`completed=false` の場合は、実装中の run があるため停止する。

`.goal-dual/plan/status.json` が存在し、`ready_for_execution=true` かつ `executed=false` の場合は、既存 plan を上書きせず停止し、引数なし `/goal-dual:run` を案内する。

`.goal-dual/plan/status.json` が存在し、`ready_for_execution=false` かつ `has_open_questions=true` の場合は、`$ARGUMENTS` を未解決事項への回答として扱い、既存 plan の意図を保ったまま plan を更新する。この場合、回答文そのものを新しいゴールとして扱わない。

## 3. 調査

実装はしないが、計画精度を上げるために以下を確認する。

- `package.json`, `pyproject.toml`, `pytest.ini`, `go.mod`, `Cargo.toml`, `pom.xml`, `build.gradle`, `*.csproj` などから eval-cmd 候補を確認する
- `rg --files` で関連しそうなファイル・テストの存在を確認する
- 既存テストがある場合、ゴールと明確に矛盾する期待値がないかを確認する

## 4. plan 生成

`.goal-dual/plan/` を作成し、以下のファイルを Write で保存する。

### plan.md

```md
# goal-dual plan

## 目的

（非エンジニアにも分かる言葉で 1〜3 行）

## 実装方針

- （何を直す・追加するか）
- （どの既存動作を壊さないか）

## 既存テストとの関係

- （矛盾がない場合は「現時点で明確な矛盾は確認していない」）
- （矛盾がある場合は、goal と期待値の食い違いを具体的に書く）

## 実行時の注意

- （Codex Work に必ず守らせること）
```

### goal.md

`/goal-dual:run` がそのまま実行できる具体的なゴール文を書く。

### acceptance-criteria.md

```md
## 完了条件

- （3〜7 個）
```

### scope.md

```md
## 変更範囲

### 変更してよい場所
- （特に制限なし）

### 変更してはいけない場所
- （特に制限なし）
```

### questions.md

未解決事項がない場合:

```md
# 未解決の確認事項

なし
```

未解決事項がある場合:

```md
# 未解決の確認事項

- （確認すべき質問）
```

### status.json

`source_goal` には `$ARGUMENTS` をそのまま入れず、同時に保存する `goal.md` の本文と同じ「実行用に確定したゴール文」を入れる。
特に、未解決事項への回答で plan を更新した場合、`source_goal` は回答文ではなく、回答を反映した確定ゴールにする。

未解決事項がない場合:

```json
{
  "status": "ready",
  "ready_for_execution": true,
  "has_open_questions": false,
  "executed": false,
  "source_goal": "goal.md と同じ確定ゴール文",
  "recommended_eval_cmd": "npm test",
  "allowed_test_changes": []
}
```

未解決事項がある場合:

```json
{
  "status": "needs_clarification",
  "ready_for_execution": false,
  "has_open_questions": true,
  "executed": false,
  "source_goal": "goal.md と同じ暫定ゴール文",
  "recommended_eval_cmd": "npm test",
  "allowed_test_changes": []
}
```

`allowed_test_changes` は、ユーザー確認済みで既存テスト期待値の変更を許可する場合のみ追加する。
未確認の矛盾がある場合は `ready_for_execution=false` にする。

## 5. 完了表示

ready の場合:

```text
=== goal-dual:plan 作成完了 ===
計画を作成しました。まだ実装は開始していません。

次のコマンドで実装を開始できます:
  /goal-dual:run

計画:
  .goal-dual/plan/plan.md
```

未解決事項がある場合:

```text
=== goal-dual:plan 確認が必要 ===
計画の下書きを作成しましたが、実装前に確認が必要です。

確認事項:
  .goal-dual/plan/questions.md

回答後、再度 /goal-dual:plan <回答内容> を実行して plan を更新してください。
```
