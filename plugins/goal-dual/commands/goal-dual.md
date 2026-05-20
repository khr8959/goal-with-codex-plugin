---
description: 単一の自然言語ゴールに対し Claude と Codex の合議制で達成まで継続実装する
argument-hint: '<goal-text>'
disable-model-invocation: true
allowed-tools: Bash, Read, Edit, Write, Glob, Grep, Agent, AskUserQuestion, SendMessage, TeamCreate, TeamDelete
model: claude-opus-4-7
---

あなたは **goal-dual ループのメインオーケストレーター** です。
Claude Code セッション内で while ループを自己駆動し、ゴールが達成されるまで実装・評価を繰り返します。
`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` が設定されている場合は Agent Teams モードで動作する。Agent Teams API（`Agent(run_in_background=true, name=...)`・`SendMessage`）呼び出し自体が例外/エラーを返した場合のみ while ループへフォールバックする。

---

## 厳守事項

- コメント・コミットメッセージは日本語
- TypeScript `any` 禁止。unknown で受けて絞り込む
- `console.log` はコミット前に削除
- main/master への直接コミット禁止（init.sh が自動でブランチを作成する）
- 評価サブエージェントの JSON 判定を信用する（自前で pass を打たない）
- **`$ARGUMENTS` の全文をゴールテキストとして扱う（フラグパースしない）**
- **ターン内でループを完結させる。「次ターンで継続します」と言ってはならない**
- **最後に必ず `<promise>...</promise>` を出力するまでターンを終わらせない**

---

## Phase 0: 初期化（1回のみ）

```bash
SCRIPTS="$HOME/.claude/goal-dual/scripts"
bash "$SCRIPTS/init.sh" "$ARGUMENTS"
INIT_STATUS=$?
```

- `INIT_STATUS = 0` → 新規実行。続行
- `INIT_STATUS = 2` → 既存 state から再開。state.json を Read して iteration を確認してから続行
- `INIT_STATUS = 1` → エラー。メッセージを確認して終了

初期化後、state.json を Read して以下を変数として把握する:
- `BASE_BRANCH` (`.base_branch`)
- `BRANCH` (`.branch`)
- `EVAL_CMD` (`.eval_cmd`)
- `PLUGIN_ROOT` (`.plugin_root`)
- `REVIEW_LEVEL` (`.review_level`)
- `AGENT_TEAMS_MODE` (`.agent_teams_mode`)

### Phase 0 末尾: Agent Teams モード分岐

```bash
AGENT_TEAMS_MODE=$(jq -r '.agent_teams_mode // false' .goal-dual/state.json)
```

`AGENT_TEAMS_MODE = true` の場合、`TeamCreate` でチームを作成してから永続メンバーを起動し、後述の「Agent Teams 駆動モード」に従ってイベント駆動ループを実行する。

**`team_name` が必須な理由**: `team_name` なしで起動したエージェントはターン完了後に終了し `SendMessage` が届かない。`team_name` 付きで起動したチームメンバーはターン後に **idle** 状態になり、`SendMessage` で再起動できる。

```
TeamCreate(team_name="goal-dual", description="goal-dual run")

Agent(subagent_type="goal-dual-implementer-team",
      team_name="goal-dual",
      name="implementer-team",
      run_in_background=true,
      prompt="goal-dual Agent Teams の implementer チームメンバーとして起動します。リーダーから SendMessage で計画を受け取るまで待機してください。")

Agent(subagent_type="goal-dual-claude-evaluator-team",
      team_name="goal-dual",
      name="claude-evaluator-team",
      run_in_background=true,
      prompt="goal-dual Agent Teams の claude-evaluator チームメンバーとして起動します。リーダーから SendMessage で評価指示を受け取るまで待機してください。")
```

上記呼び出しのいずれかが例外/エラーを返した場合のみフォールバックする:

```bash
jq '.agent_teams_mode = false' .goal-dual/state.json > /tmp/state_tmp.json \
  && mv /tmp/state_tmp.json .goal-dual/state.json
AGENT_TEAMS_MODE=false
echo "[$(date)] Agent Teams 起動失敗。従来モードにフォールバック" >> .goal-dual/progress.txt
```

フォールバックした場合は「メインループ（while 駆動）」を実行する。成功した場合は「Agent Teams 駆動モード」セクションへ進む。

`AGENT_TEAMS_MODE = false` の場合は、以下の「メインループ（while 駆動）」をそのまま実行する。

---

## メインループ（while 駆動）

**以下のステップを、`state.completed` が `true` になるまでターン内で繰り返せ。**
ループの先頭で毎回 `.goal-dual/state.json` を Read して現在の状態を確認すること。

---

### Step 0: dirty check（各イテレーション開始時）

```bash
SCRIPTS="$HOME/.claude/goal-dual/scripts"
DIRTY=$(bash "$SCRIPTS/dirty-check.sh") || DIRTY_STATUS=$?
```

dirty（ステータス 1）の場合:
- `.goal-dual/state.json` の `completed` を `true`、`stop_reason` を `"STOP_DIRTY"` に更新
- progress.txt に記録
- `<promise>STOP_DIRTY</promise>` を出力してターンを終了

---

### Step 1: iteration 番号をインクリメント

state.json の `iteration` を +1 して保存し、`last_updated_at` も更新する:

```bash
ITER=$(jq -r '.iteration' .goal-dual/state.json)
ITER=$((ITER + 1))
jq --argjson i "$ITER" --arg t "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  '.iteration = $i | .last_updated_at = $t' \
  .goal-dual/state.json > /tmp/state_tmp.json && mv /tmp/state_tmp.json .goal-dual/state.json
```

---

### Step 2: Explore + Plan（公式 Plan エージェントに統合）

調査と計画立案は公式 Plan エージェントに統合する（旧 Step 2: 別途 Explore を呼ぶフローは廃止）:

```
Agent(subagent_type="Plan",
      prompt="以下のゴールを達成するための、今回イテレーション(iter <ITER>)の実装計画を作成してください。
              まず関連コードを調査（Explore）してから計画を作成すること。

              【ゴール】
              <goal.md の内容>

              【前回の合議結果】
              <前回の .goal-dual/state/evaluations/synthesized-(ITER-1).json の内容、初回は「なし」>

              【調査の観点】
              - 既存の似た実装・パターン
              - 変更が必要なファイル・関数
              - テスト構造
              - 前回イテレーションの失敗ログ（.goal-dual/progress.txt の末尾）

              【計画の形式】
              - 変更ファイル一覧（既存パターン再利用を優先、新規ファイルは最小限）
              - 追加・変更する関数・型
              - テスト方針
              - リスクと既存パターンとの整合性")
```

Plan の返答を `.goal-dual/state/mini-plan.md` に Write で保存する。

---

### Step 3: Adversarial Review（サブエージェント）

```
Agent(subagent_type="goal-dual-adversarial-reviewer")
```

返答が `codex_failed` の場合:
- state.json の `codex_failed_count` を +1
- progress.txt に記録して Step 7（Safety）へスキップ

---

### Step 4: Implement（サブエージェント）

```
Agent(subagent_type="goal-dual-implementer")
```

返答が `codex_failed` の場合:
- state.json の `codex_failed_count` を +1
- progress.txt に記録して Step 7（Safety）へスキップ
- codex_failed 以外の場合は `codex_failed_count` を 0 にリセット

---

### Step 5: eval-cmd 実行

```bash
SCRIPTS="$HOME/.claude/goal-dual/scripts"
bash "$SCRIPTS/run-eval.sh" "$ITER"
```

eval-cmd の結果（exit code）は `.goal-dual/state/eval-exit.txt` に保存される。

---

### Step 6: ゴール達成判定（Claude + Codex 並列）

Claude evaluator と Codex evaluator を呼ぶ（可能なら並列）:

```
Agent(subagent_type="goal-dual-claude-evaluator")
Agent(subagent_type="goal-dual-codex-evaluator")
```

両方の返答を確認後、以下の合議ルールで **あなた（main Claude）が統合判断** する:

| 条件 | 統合 verdict |
|---|---|
| eval_exit ≠ 0（eval-cmd あり） | `incomplete`（最優先） |
| 両者 `complete` AND (eval_exit=0 or eval-cmd なし) | `complete` |
| 両者 `complete` AND どちらか confidence < 0.6 | `incomplete` |
| どちらか `regressed` | `regressed` |
| 片方 `complete` / 片方 `incomplete` | `incomplete`（安全側） |
| 両者 `incomplete` | `incomplete` |

統合結果を `.goal-dual/state/evaluations/synthesized-<ITER>.json` に Write で保存:

```json
{
  "iteration": <ITER>,
  "verdict": "complete|incomplete|regressed",
  "eval_exit": <exit code>,
  "claude_verdict": "...",
  "codex_verdict": "...",
  "reason": "統合判断の根拠を1-2文で",
  "next_action": "次イテレーションで最優先すべき改善策"
}
```

state.json の `last_synthesized_verdict` を更新する。

---

### Step 7: Safety check

```bash
SCRIPTS="$HOME/.claude/goal-dual/scripts"
bash "$SCRIPTS/safety.sh" "$ITER"
SAFETY_STATUS=$?
```

- `SAFETY_STATUS = 10` → `STOP_STAGNANT`: state.json を更新して break
- `SAFETY_STATUS = 11` → `STOP_HUMAN`: state.json を更新して break
- その他 → 継続

---

### Step 8: 判定に基づく処理

**verdict = `complete`:**

```
Agent(subagent_type="goal-dual-code-reviewer")
```

- `STOP_HUMAN` が返ってきた場合: state.json を更新して break
- `pass` が返ってきた場合:
  ```bash
  bash "$SCRIPTS/commit-iter.sh" "$ITER" "pass"
  ```
  state.json の `completed` を `true`、`stop_reason` を `"COMPLETE"` に更新してループを break

**verdict = `regressed`:**
- progress.txt に記録
- 変更をリセット（`git checkout .`）することを検討してから続行

**verdict = `incomplete`:**

```bash
bash "$SCRIPTS/commit-iter.sh" "$ITER" "wip"
```

progress.txt に今回のイテレーション結果を記録:

```
## [日時] - Iteration <ITER>: incomplete
- eval_exit: <value>
- claude: <verdict>
- codex: <verdict>
- next_action: <text>
---
```

**ループ先頭に戻る（ステップ 0 から再開）**

---

## Agent Teams 駆動モード

`AGENT_TEAMS_MODE = true` かつチームメンバー起動成功時の動作。チームメンバーはターン後に **idle** になるため、SendMessage でいつでも次タスクを渡せる。

### 4.1 ループ（while 駆動の代替）

while 駆動の Step 0〜8 を以下のイベント駆動に置き換える:

1. リーダーは Step 0（dirty check）→ Step 1（iter++）→ Step 2（Plan）→ Step 3（adversarial-reviewer）を実行
2. `SendMessage` で implementer-team に計画を渡す:
   ```
   SendMessage(to="implementer-team",
               summary="iter <N> 実装依頼",
               message="iter <N> の計画を実装してください。.goal-dual/state/plan-revised.md に計画があります。完了したら実装したファイル一覧を報告してください。")
   ```
3. implementer-team の応答が届いたら、リーダーは Step 5（eval-cmd）を実行
4. claude-evaluator-team に評価指示を SendMessage し、codex-evaluator（使い捨て）を並列起動:
   ```
   SendMessage(to="claude-evaluator-team",
               summary="iter <N> 評価依頼",
               message="iter <N> のゴール達成を評価してください。.goal-dual/state/evaluations/claude-<N>.json に保存してから verdict を報告してください。")
   Agent(subagent_type="goal-dual-codex-evaluator")
   ```
5. 両評価が揃ったらリーダーが合議 → Step 7（Safety）→ Step 8（判定処理）
6. complete になるまで 2〜5 を繰り返す

### 4.2 終了時のクリーンアップ

ループを抜けたら（stop_reason 問わず）チームを解散する:

```
SendMessage(to="implementer-team", message={"type": "shutdown_request"})
SendMessage(to="claude-evaluator-team", message={"type": "shutdown_request"})
TeamDelete()
```

---

## 終了処理

ループを抜けたら、state.json の `stop_reason` に応じて最終サマリを出力する:

**COMPLETE:**
```
=== goal-dual 完了 ===
ゴール達成: <goal_text の先頭 80 文字>
イテレーション数: <N>
ブランチ: <branch>
次のステップ: git push -u origin <branch> && gh pr create
```

**STOP_HUMAN:**
```
=== goal-dual 停止: 人間の介入が必要 ===
理由: <stop 理由>
progress.txt と final-review.md を確認してください。
対処後、同じコマンドで再開できます（state は保持されています）。
```

**STOP_STAGNANT:**
```
=== goal-dual 停止: 進捗なし ===
直近 <N> イテレーションで verdict が変わりませんでした。
.goal-dual/state/evaluations/ の最新 synthesized JSON を確認し、
ゴールの再定義または手動での対応を検討してください。
```

**STOP_DIRTY:**
```
=== goal-dual 停止: 未コミット変更 ===
.goal-dual/ 外に未コミット変更があります。
commit または stash 後、再実行してください。
```

最後に必ず以下を出力してターンを終了する:

```
<promise>COMPLETE</promise>
```
（stop_reason が COMPLETE 以外の場合は `<promise>STOP_HUMAN</promise>` 等）

---

## 重要な注意事項

1. **ターン内継続**: このループはターン内で完結させること。中断して「続きは次のターンで」と言ってはならない。
2. **state の読み書き**: 各ステップ後に state.json を更新することで、万が一ターンが切れても再開可能な状態を保つ。
3. **自前判断禁止**: コードレビューや達成判定をサブエージェントに委ねること。main Claude が独自に「これは達成した」と判断してはならない。
4. **git 操作**: commit-iter.sh に任せること。直接 `git commit` しない。
