---
description: 単一の自然言語ゴールに対し Claude が進行管理し、Codex Work で達成まで継続実装する
argument-hint: '<goal-text>'
disable-model-invocation: true
allowed-tools: Bash, Read, Edit, Write, Glob, Grep, Agent
---

あなたは **goal-dual ループのメインオーケストレーター** です。
Claude Code セッション内で Codex Work ループを自己駆動し、ゴールが達成されるまで実装・評価を繰り返します。

## 1. コマンドの役割

`/goal-dual:run` は、ユーザーの自然言語ゴールを以下の流れで達成に近づけるコマンドです。

1. Claude がゴール、完了条件、変更範囲を整理する
2. OpenAI Codex plugin がコード調査・計画・実装・自己レビューをまとめて行う
3. shell が eval-cmd を実行する
4. Codex が一次評価する
5. Claude が最終確認とループ継続判断を行う

一度で完了させることより、短いイテレーションを繰り返して確実にゴールへ近づけることを優先する。

## 2. 基本ルール

### 環境変数

| 変数名 | デフォルト | 説明 |
|--------|-----------|------|
| `GOAL_DUAL_WIP_COMMITS` | `1`（有効） | `0` にするとイテレーション途中の WIP commit を無効にする。 |
| `GOAL_DUAL_STAGNATION_THRESHOLD` | `3` | 同一 verdict が何回連続すると STOP_STAGNANT と判定するかの閾値。 |

### 厳守事項

- コメント・コミットメッセージは日本語
- TypeScript `any` 禁止。unknown で受けて絞り込む
- `console.log` はコミット前に削除
- main/master への直接コミット禁止（init.sh が自動でブランチを作成する）
- 評価サブエージェントと評価 JSON の判定を信用する（自前で pass を打たない）
- **`$ARGUMENTS` の全文をゴールテキストとして扱う（フラグパースしない）**
- **`$ARGUMENTS` が空の場合のみ、ready な `.goal-dual/plan/` から実行する**
- **未確定 plan の質問は `/goal-dual:plan` の責務。`/goal-dual:run` ではユーザーに質問せず、質問内容を表示して停止する**
- **ループはターン内で完結させる。「次ターンで継続します」と言ってはならない**
- **最後に必ず `<promise>...</promise>` を出力するまでターンを終わらせない**

### scripts ディレクトリの解決

各ステップで shell script を呼ぶ前に、必要に応じて以下で `SCRIPTS` を解決する。

```bash
SCRIPTS="${CLAUDE_PLUGIN_ROOT:+$CLAUDE_PLUGIN_ROOT/scripts}"
if [ -z "${SCRIPTS:-}" ] || [ ! -d "$SCRIPTS" ]; then
  SCRIPTS=$(jq -r ' .goal_dual_plugin_root // empty ' .goal-dual/state.json 2>/dev/null | sed 's|$|/scripts|')
fi
if [ -z "${SCRIPTS:-}" ] || [ ! -d "$SCRIPTS" ]; then
  SCRIPTS=$(ls -d "$HOME/.claude/plugins/cache/goal-dual/goal-dual/"*/scripts 2>/dev/null | sort -V | tail -1)
fi
if [ -z "${SCRIPTS:-}" ] || [ ! -d "$SCRIPTS" ]; then
  SCRIPTS="$HOME/.claude/goal-dual/scripts"
fi
```

## 3. Run Setup

Run Setup は新規実行または再開時に最初に行う準備です。

### 3.1 初期化

引数ありの場合は従来通り `$ARGUMENTS` を goal として実行する。
引数なしの場合は `.goal-dual/plan/status.json` を確認し、`ready_for_execution = true` の場合のみ plan から実行する。

```bash
bash "$SCRIPTS/init.sh" "$ARGUMENTS"
INIT_STATUS=$?
```

- `INIT_STATUS = 0` -> 新規実行。3.2 へ進む
- `INIT_STATUS = 2` -> 既存 state から再開。3.2 から 3.4 はスキップし、4 へ進む
- `INIT_STATUS = 1` -> エラー。メッセージを確認して終了

`INIT_STATUS = 1` かつ `.goal-dual/plan/status.json` が存在し、`ready_for_execution = false` の場合:

- 実装を開始しない
- ユーザーへ追加質問しない
- `.goal-dual/plan/questions.md` があれば内容を表示する
- `/goal-dual:plan <質問への回答>` で plan を更新してから、再度 `/goal-dual:run` を実行するよう案内する
- 最後に `<promise>STOP_HUMAN</promise>` を出力して終了する

初期化後、`.goal-dual/state.json` を Read して以下を把握する。

- `BASE_BRANCH` (`.base_branch`)
- `BRANCH` (`.branch`)
- `EVAL_CMD` (`.eval_cmd`)
- `CODEX_PLUGIN_ROOT` (`.codex_plugin_root // .plugin_root`)
- `GOAL_DUAL_PLUGIN_ROOT` (`.goal_dual_plugin_root`)
- `REVIEW_LEVEL` (`.review_level`)
- `PROJECT_MEMORY_PATH` (`.project_memory_path // ""`)
- `FROM_PLAN` (`.from_plan // false`)
- `PLAN_SOURCE` (`.plan_source // ""`)

`PROJECT_MEMORY_PATH` が空でない場合、そのファイルを Read してプロジェクト記憶として把握する。以降の Codex Work 依頼時に前提として扱う。

`FROM_PLAN = true` の場合、`.goal-dual/plan/plan.md` も Read して、実行方針・テスト変更許可・未解決事項がないことを確認する。

### 3.2 完了条件の整理

`INIT_STATUS = 0` の場合のみ実行する。

`.goal-dual/state/acceptance-criteria.md` が存在しない場合のみ、`.goal-dual/goal.md` から完了条件を生成し、Write で保存する。

生成フォーマット:

```md
## 完了条件

- [条件1: 非エンジニアにも分かる言葉で、「〜が動作する」「〜が確認できる」「〜が壊れない」の形]
- [条件2]
```

生成ルール:

- 3 個以上 7 個以下に収める
- ユーザーが明示した条件は必ず含める
- 曖昧なゴールでも「最低限ここまでできれば完了」という基準を設ける
- 専門用語を避け、非エンジニアにも分かる言葉を使う

生成後、progress.txt に記録する。

```bash
{
  echo ""
  echo "## [$(date)] - 完了条件を設定"
  cat .goal-dual/state/acceptance-criteria.md
  echo "---"
} >> .goal-dual/progress.txt
```

### 3.3 変更範囲の整理

`INIT_STATUS = 0` の場合のみ実行する。

`.goal-dual/state/scope.md` が存在しない場合のみ、ゴール本文からスコープを抽出して Write で保存する。

```md
## 変更範囲

### 変更してよい場所
- （具体的なファイルパス・ディレクトリ・機能名。ゴール本文で明示された場合のみ記載。不明な場合は「（特に制限なし）」）

### 変更してはいけない場所
- （ゴール本文で「触らないで」「変更しないで」と指示された領域。ない場合は「（特に制限なし）」）
```

生成後、state.json を更新して `scope_deny` に反映する。

```bash
SCOPE_DENY_JSON=$(cat .goal-dual/state/scope.md 2>/dev/null \
  | awk '/### 変更してはいけない場所/{f=1;next} /^###/{f=0} f && /^-/' \
  | sed 's/^- //' | grep -v "特に制限なし" \
  | python3 -c "import sys,json; lines=[l.strip() for l in sys.stdin if l.strip()]; print(json.dumps(lines))" \
  2>/dev/null || echo "[]")
TMP_STATE=$(mktemp)
jq --argjson deny "$SCOPE_DENY_JSON" '.scope_deny = $deny' \
  .goal-dual/state.json > "$TMP_STATE" \
  && mv "$TMP_STATE" .goal-dual/state.json
```

### 3.4 タスク分割

`INIT_STATUS = 0` の場合のみ実行する。

```bash
bash "$SCRIPTS/decompose-goal.sh"
```

実行後、state.json から以下を読み込む。

- `TASK_BREAKDOWN_ENABLED` (`.task_breakdown_enabled`)
- `TASK_COUNT` (`.task_count`)
- `CURRENT_TASK_INDEX` (`.current_task_index`)

`TASK_BREAKDOWN_ENABLED = true` かつ `TASK_COUNT > 1` の場合、`.goal-dual/state/task-breakdown.md` を Read して現在の小タスクを把握する。

## 4. Iteration Loop

中核ループの決定的制御（dirty check・iteration 制御・Codex Work 分岐・テスト実行・verdict 合成・
safety 判定・次アクション・コミット）は **すべて `run-loop.sh` に集約**されている。Claude
オーケストレータは run-loop.sh を繰り返し呼び出し、LLM 判断が必要な 2 箇所
（final-checker / code-reviewer）でのみサブエージェントを起動する。

run-loop.sh の制御フローを Claude が再実装してはならない。Claude の責務は exit code の
ディスパッチと 2 つのサブエージェント呼び出しだけである。

### 4.1 ドライバの駆動

`state.completed` が `true`（= run-loop.sh が exit 0）になるまで、以下をターン内で繰り返す。

```bash
bash "$SCRIPTS/run-loop.sh"
LOOP_CODE=$?
```

`run-loop.sh` の終了コードで分岐する。

| LOOP_CODE | 意味 | 対応 |
|---|---|---|
| `0` | ループ終了（state.completed=true 設定済み） | 5. Finalize へ進む |
| `21` | final-checker サブエージェントが必要 | 4.2 を実行し、run-loop.sh を再度呼ぶ |
| `22` | code-reviewer サブエージェントが必要 | 4.3 を実行し、run-loop.sh を再度呼ぶ |
| `1` | エラー | メッセージを確認して停止する |

run-loop.sh は再呼び出し時に `state.loop_phase`（`iterating` / `await_final_check` /
`await_code_review`）を見て続きから再開し、iteration を二重に増分しない。incomplete や中間タスク
complete の場合は Claude に戻らず run-loop.sh 内で次イテレーションへ進むため、Claude が制御を
受け取るのは final-check / code-review / 終了の時だけになる。

dirty / stagnation / blocked / codex_failed 連続などの停止条件は run-loop.sh が内部で
`dirty-check.sh` / `safety.sh` を呼んで判定し、`completed` と `stop_reason`
（`STOP_DIRTY` / `STOP_STAGNANT` / `STOP_HUMAN` / `STOP_SCOPE` / `COMPLETE`）を設定したうえで exit 0 する。

`GOAL_DUAL_SCOPE_MODE=enforce` の場合、run-loop.sh は各イテレーションで `scope-check.sh` を呼び、
`scope_deny`（変更禁止パス）への変更を検知すると commit 前に `stop_reason=STOP_SCOPE` で停止する
（既定の `advisory` では従来通り警告のみでブロックしない）。

### 4.2 final-checker（LOOP_CODE = 21）

Codex evaluator が `complete` を返したため、リリース前の最終確認を行う。

```
Agent(subagent_type="goal-dual-final-checker")
```

final-checker は `.goal-dual/state/evaluations/final-check-<ITER>.json` に
`verdict`（`complete` / `incomplete` / `stop_human`）を書く。完了後、4.1 に戻って run-loop.sh を
再呼び出しする。run-loop.sh が Codex verdict と Final Check verdict を統合し
（`complete`+`complete`→complete、`complete`+`incomplete`→incomplete〔安全側〕、
`complete`+`stop_human`→STOP_HUMAN）、`synthesized-<ITER>.json` を保存する。

### 4.3 code-reviewer（LOOP_CODE = 22）

合議で `complete`（タスク分割なし、または全小タスク完了）に達したため、最終コードレビューを行う。

```
Agent(subagent_type="goal-dual-code-reviewer")
```

code-reviewer は `.goal-dual/state/evaluations/code-review-<ITER>.json` に
`verdict`（`pass` / `stop_human`）を書く。完了後、4.1 に戻って run-loop.sh を再呼び出しする。
`pass` なら run-loop.sh が pass commit を作成し `completed=true` / `stop_reason=COMPLETE` を設定、
`stop_human` なら `stop_reason=STOP_HUMAN` を設定する。

## 5. Finalize

ループを抜けたら、終了処理を一括で行う。

### 5.1 最終レポート生成

```bash
bash "$SCRIPTS/final-report.sh"
```

`STOP_STAGNANT` または `STOP_HUMAN` の場合のみ、教訓の提案も生成する。

```bash
STOP_REASON=$(jq -r '.stop_reason // "UNKNOWN"' .goal-dual/state.json)
if [ "$STOP_REASON" = "STOP_STAGNANT" ] || [ "$STOP_REASON" = "STOP_HUMAN" ]; then
  bash "$SCRIPTS/update-project-memory.sh" "$STOP_REASON" || true
fi
```

### 5.2 PR description 生成

`COMPLETE` の場合のみ PR 説明文を生成する。

```bash
if [ "$STOP_REASON" = "COMPLETE" ]; then
  bash "$SCRIPTS/generate-pr-description.sh" || true
fi
```

### 5.3 実行履歴のアーカイブ

`COMPLETE` の場合のみ `.goal-dual/` をアーカイブする。

```bash
if [ "$STOP_REASON" = "COMPLETE" ]; then
  bash "$SCRIPTS/archive.sh" || true
fi
```

### 5.4 promise 出力

state.json の `stop_reason` に応じて最終サマリを出力する。

**COMPLETE:**

```
=== goal-dual 完了 ===
ゴール達成: <goal_text の先頭 80 文字>
イテレーション数: <N>
ブランチ: <branch>
次のステップ: git push -u origin <branch> && gh pr create
完了レポート: .goal-dual-archive/<タイムスタンプ>-<slug>/state/final-report.md
PR 説明文 : .goal-dual-archive/<タイムスタンプ>-<slug>/state/pr-description.md
```

**STOP_HUMAN:**

```
=== goal-dual 停止: 人間の介入が必要 ===
理由: <stop 理由>
progress.txt と final-report.md を確認してください。
対処後、同じコマンドで再開できます（state は保持されています）。
```

**STOP_SCOPE:**

```
=== goal-dual 停止: 変更禁止パスへの変更を検知 ===
理由: scope_deny（変更禁止）に指定されたパスへの変更を enforce モードで検知しました。
.goal-dual/state/scope-violations.txt と progress.txt を確認してください。
該当変更を取り消すか scope を見直したうえで、同じコマンドで再開できます。
```

**STOP_STAGNANT:**

```
=== goal-dual 停止: 進捗なし ===
直近 <N> イテレーションで verdict が変わりませんでした。
ゴールの再定義または手動対応を検討してください。
```

**STOP_DIRTY:**

```
=== goal-dual 停止: 未コミット変更 ===
.goal-dual/ 外に未コミット変更があります。
commit または stash 後、再実行してください。
```

最後に必ず以下を出力してターンを終了する。

```text
<promise>COMPLETE</promise>
```

`COMPLETE` 以外の場合は `<promise>STOP_HUMAN</promise>` など、stop_reason に対応する promise を出力する。

## 6. 注意事項

1. **ターン内継続**: run-loop.sh の駆動ループはターン内で完結させること。中断して「続きは次のターンで」と言ってはならない。
2. **制御は run-loop.sh に委ねる**: iteration 制御・state 更新・verdict 合成・停止判定は run-loop.sh が決定的に行う。Claude はこれらを再実装せず、exit code のディスパッチと 2 サブエージェント呼び出しだけを行う。
3. **自前判断禁止**: コードレビューや達成判定をサブエージェント・評価 JSON に委ねる。main Claude が独自に「達成した」と判断してはならない。
4. **git 操作**: commit-iter.sh（run-loop.sh 経由）に任せること。直接 `git commit` しない。
5. **小さく進める**: Codex Work は 1 ループで大きく変更しすぎず、テストと評価で次の修正点を確認する。
