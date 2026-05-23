---
description: 単一の自然言語ゴールに対し Claude と Codex の合議制で達成まで継続実装する
argument-hint: '<goal-text>'
disable-model-invocation: true
allowed-tools: Bash, Read, Edit, Write, Glob, Grep, Agent, AskUserQuestion, SendMessage, TeamCreate, TeamDelete
---

あなたは **goal-dual ループのメインオーケストレーター** です。
Claude Code セッション内で while ループを自己駆動し、ゴールが達成されるまで実装・評価を繰り返します。

**通常モード（安定版）**: `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` が未設定の場合。ターン内で while ループを完結させる。ほとんどのユーザーはこちらを使う。

**Agent Teams モード（実験的）**: `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` が設定されている場合のみ有効。Agent Teams API（`Agent(run_in_background=true, name=...)`・`SendMessage`）を使ったマルチターン設計で動作する。API 自体が例外/エラーを返した場合のみ while ループへフォールバックする。

---

## 厳守事項

- コメント・コミットメッセージは日本語
- TypeScript `any` 禁止。unknown で受けて絞り込む
- `console.log` はコミット前に削除
- main/master への直接コミット禁止（init.sh が自動でブランチを作成する）
- 評価サブエージェントの JSON 判定を信用する（自前で pass を打たない）
- **`$ARGUMENTS` の全文をゴールテキストとして扱う（フラグパースしない）**
- **通常モード（while 駆動）はターン内でループを完結させる。「次ターンで継続します」と言ってはならない**
- **Agent Teams モード（`agent_teams_mode=true`）はマルチターン設計に従う:**
  - 1 ターンで 1 フェーズのみ実行し、永続メンバーへ `SendMessage` したら必ずターンを切る
  - `state.json` の `agent_teams_phase` で現在位置を保存し、次ターンで再構築する
  - ターンを切る前に必ず `agent_teams_phase` / `agent_teams_pending_from` を state.json に書き込む
- **最後に必ず `<promise>...</promise>` を出力するまでターンを終わらせない（両モード共通）**

---

## Phase 0: 初期化（1回のみ）

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
- `CODEX_PLUGIN_ROOT` (`.codex_plugin_root // .plugin_root`)
- `GOAL_DUAL_PLUGIN_ROOT` (`.goal_dual_plugin_root`)
- `REVIEW_LEVEL` (`.review_level`)
- `AGENT_TEAMS_MODE` (`.agent_teams_mode`)
- `PROJECT_MEMORY_PATH` (`.project_memory_path // ""`)

`PROJECT_MEMORY_PATH` が空でない場合、そのファイルを Read してプロジェクト記憶として把握する。以降の Plan・Implement で参照すること。

---

### Phase 0.5: 完了条件整理（新規実行時のみ）

`INIT_STATUS = 0` の場合のみ実行（`INIT_STATUS = 2` の再開時はスキップ）。

`.goal-dual/state/acceptance-criteria.md` が存在するか確認する:

```bash
ls .goal-dual/state/acceptance-criteria.md 2>/dev/null && echo "exists" || echo "missing"
```

ファイルが **存在しない場合のみ**、ゴール本文（`.goal-dual/goal.md` を Read する）から完了条件を生成し、Write で `.goal-dual/state/acceptance-criteria.md` に保存する。

**生成フォーマット:**

```md
## 完了条件

- [条件1: 非エンジニアにも分かる言葉で、「〜が動作する」「〜が確認できる」「〜が壊れない」の形]
- [条件2]
- ...（3〜7 個）
```

**生成ルール:**
- 専門用語を避け、非エンジニアにも分かる言葉を使う
- 3 個以上 7 個以下に収める
- ユーザーが明示した条件は必ず含める
- 曖昧なゴールでも「最低限ここまでできれば完了」という基準を設ける

生成後、progress.txt に記録する:

```bash
{
  echo ""
  echo "## [$(date)] - 完了条件を設定"
  cat .goal-dual/state/acceptance-criteria.md
  echo "---"
} >> .goal-dual/progress.txt
```

---

### Phase 0.7: 変更範囲の整理（新規実行時のみ）

`INIT_STATUS = 0` の場合のみ実行（`INIT_STATUS = 2` の再開時はスキップ）。

`.goal-dual/state/scope.md` が存在しない場合のみ、ゴール本文からスコープを抽出して Write で保存する。

```md
## 変更範囲

### 変更してよい場所
- （具体的なファイルパス・ディレクトリ・機能名。ゴール本文で明示された場合のみ記載。不明な場合は「（特に制限なし）」）

### 変更してはいけない場所
- （ゴール本文で「触らないで」「変更しないで」と指示された領域。ない場合は「（特に制限なし）」）
```

**抽出ルール:**
- ゴール本文に「〜だけ変更」「〜は触らないで」等の表現があれば対応するエントリを記載
- 明示的な制限がない場合は両方とも「（特に制限なし）」
- ファイルパスは glob 的パターン（`src/api/**` など）でも可

生成後、state.json を更新して scope 情報を保存する:

```bash
SCOPE_DENY_JSON=$(cat .goal-dual/state/scope.md 2>/dev/null \
  | awk '/### 変更してはいけない場所/{f=1;next} /^###/{f=0} f && /^-/' \
  | sed 's/^- //' | grep -v "特に制限なし" \
  | python3 -c "import sys,json; lines=[l.strip() for l in sys.stdin if l.strip()]; print(json.dumps(lines))" \
  2>/dev/null || echo "[]")
jq --argjson deny "$SCOPE_DENY_JSON" '.scope_deny = $deny' \
  .goal-dual/state.json > /tmp/state_tmp.json \
  && mv /tmp/state_tmp.json .goal-dual/state.json
```

---

### Phase 0.8: タスク分割（新規実行時のみ）

`INIT_STATUS = 0` の場合のみ実行（`INIT_STATUS = 2` の再開時はスキップ）。

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
bash "$SCRIPTS/decompose-goal.sh"
```

実行後、state.json から以下を読み込む:
- `TASK_BREAKDOWN_ENABLED` (`.task_breakdown_enabled`)
- `TASK_COUNT` (`.task_count`)
- `CURRENT_TASK_INDEX` (`.current_task_index`)

`TASK_BREAKDOWN_ENABLED = true` かつ `TASK_COUNT > 1` の場合: `.goal-dual/state/task-breakdown.md` を Read して現在の小タスクを把握する。

---

### Phase 0 末尾: Agent Teams モード分岐

```bash
AGENT_TEAMS_MODE=$(jq -r '.agent_teams_mode // false' .goal-dual/state.json)
AGENT_TEAMS_PHASE=$(jq -r '.agent_teams_phase // "init"' .goal-dual/state.json)
```

`AGENT_TEAMS_MODE = true` の場合、後述の「Agent Teams 駆動モード」に従ってマルチターン設計で動作する。

**`team_name` が必須な理由**: `team_name` なしで起動したエージェントはターン完了後に終了し `SendMessage` が届かない。`team_name` 付きで起動したチームメンバーはターン後に **idle** 状態になり、`SendMessage` で再起動できる。

**フェーズ判断**:

- `AGENT_TEAMS_PHASE = "init"` かつ `INIT_STATUS = 0`（新規）→ TeamCreate してからメンバーを起動し、init フェーズ処理へ
- `AGENT_TEAMS_PHASE` が他の値（再開）→ TeamCreate をスキップして既存 phase にディスパッチする

新規起動時のみ TeamCreate とメンバー起動を実行:

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

起動直後に state.json へ phase を書き込む:

```bash
jq '.agent_teams_phase = "init" | .agent_teams_pending_from = []' \
  .goal-dual/state.json > /tmp/state_tmp.json \
  && mv /tmp/state_tmp.json .goal-dual/state.json
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

              【完了条件（最優先で参照すること）】
              <.goal-dual/state/acceptance-criteria.md の内容>

              【現在の小タスク（タスク分割が有効な場合のみ）】
              <TASK_BREAKDOWN_ENABLED=true の場合: task-breakdown.md のうち CURRENT_TASK_INDEX 番のタスクのみ実装すること。全体ゴールではなく現在の小タスクだけに集中する>

              【プロジェクト記憶（.goal-dual-memory.md がある場合のみ）】
              <PROJECT_MEMORY_PATH が設定されている場合、そのファイルの内容。古い情報が残る可能性があるため参考として扱い、現在のコードを優先する>

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
              - テスト方針（完了条件の各項目をどう確認するか）
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

両方の返答を確認後、以下の合議ルールで **あなた（main Claude）が統合判断** する。
判断前に `.goal-dual/state/acceptance-criteria.md` を Read し、完了条件の各項目が満たされているか確認すること。

| 条件 | 統合 verdict |
|---|---|
| eval_exit ≠ 0（eval-cmd あり） | `incomplete`（最優先） |
| 完了条件に未達項目がある | `incomplete`（eval_exit=0 でも） |
| 両者 `complete` AND (eval_exit=0 or eval-cmd なし) AND 完了条件すべて達成 | `complete` |
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
bash "$SCRIPTS/safety.sh" "$ITER"
SAFETY_STATUS=$?
```

- `SAFETY_STATUS = 10` → `STOP_STAGNANT`: state.json を更新して break
- `SAFETY_STATUS = 11` → `STOP_HUMAN`: state.json を更新して break
- その他 → 継続

---

### Step 8: 判定に基づく処理

**verdict = `complete`:**

タスク分割が有効（`TASK_BREAKDOWN_ENABLED = true`）かつ `CURRENT_TASK_INDEX < TASK_COUNT` の場合:
- 現在の小タスクが完了したとみなし、`current_task_index` を +1 して state.json を更新
- `commit-iter.sh wip` でコミットしてからループ先頭に戻る（全体完了ではない）

```bash
NEXT_IDX=$((CURRENT_TASK_INDEX + 1))
jq --argjson idx "$NEXT_IDX" '.current_task_index = $idx' \
  .goal-dual/state.json > /tmp/state_tmp.json && mv /tmp/state_tmp.json .goal-dual/state.json
bash "$SCRIPTS/commit-iter.sh" "$ITER" "wip"
# ループ先頭へ戻る（次の小タスクを実行）
```

それ以外（タスク分割なし、または全小タスク完了）の場合:

```
Agent(subagent_type="goal-dual-code-reviewer")
```

- `STOP_HUMAN` が返ってきた場合: state.json を更新して break
- `pass` が返ってきた場合:
  ```bash
  bash "$SCRIPTS/commit-iter.sh" "$ITER" "pass"
  ```
  state.json の `completed` を `true`、`stop_reason` を `"COMPLETE"` に更新し、ループを break
  （archive は終了処理セクションで final-report.sh / generate-pr-description.sh の後に実行する）

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

## Agent Teams 駆動モード（実験的・マルチターン設計）

> **注意**: これは実験的機能です。`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` が設定されていない場合は
> このセクションを読む必要はありません。通常利用は「メインループ（while 駆動）」を使ってください。

`AGENT_TEAMS_MODE = true` かつチームメンバー起動成功時の動作。

### 原則

- **1 ターン 1 アクション**。SendMessage 後は必ずターンを切る。
- **state.json の `agent_teams_phase`** を毎ターン最初に Read し、対応する処理にディスパッチする。
- 永続メンバーから受信したメッセージはこのターンの入力（メッセージプロンプト）として渡される。受信内容を解釈して phase を進める。

### Phase ディスパッチ

| 現在 phase | 受信メッセージ | このターンでやること | 次の phase |
|-----------|---------------|----------------------|------------|
| `init` | なし / `/goal-dual` 起動 | Step 0 dirty → Step 1 iter++ → Step 2 Plan → Step 3 adversarial → SendMessage(impl) | `impl_requested` |
| `impl_requested` | implementer-team の `implemented: ...` or `codex_failed` | Step 5 eval-cmd → SendMessage(eval-team) + Agent(codex-evaluator) | `eval_requested` |
| `eval_requested` | claude-evaluator-team の `evaluated: ...` | 合議 → synthesized.json 保存 → Safety → 判定処理 | `iteration_done` か `finalizing` |
| `iteration_done` | （内部遷移） | phase を `init` に戻して同ターンで次イテレーション開始 または ターンを切る | `init` |
| `finalizing` | （内部遷移） | SendMessage(impl, shutdown) / SendMessage(eval-team, shutdown) | `shutdown` |
| `shutdown` | shutdown_response（両方）or タイムアウト | TeamDelete → 終了処理セクションへ移行 | COMPLETE |

### 各 phase の擬似コード

```
PHASE=$(jq -r '.agent_teams_phase // "init"' .goal-dual/state.json)
case "$PHASE" in
  init)
    # Step 0: dirty check
    # Step 1: iter++ → state.json 更新
    # Step 2: Agent(Plan) → plan-revised.md 保存
    # Step 3: Agent(adversarial-reviewer)
    # SendMessage(to="implementer-team", summary="iter <N> 実装依頼",
    #   message="iter <N> の計画を実装してください。.goal-dual/state/plan-revised.md に計画があります。
    #            完了したら実装ファイル一覧をスペース区切りで報告してください（形式: implemented: file1 file2）。
    #            失敗した場合は codex_failed を返してください。")
    # state.agent_teams_phase = "impl_requested"
    # state.agent_teams_pending_from = ["implementer-team"]
    # state.agent_teams_last_msg_iter = <ITER>
    # state.agent_teams_last_msg_at = <ISO8601>
    # <promise>WAITING_IMPLEMENTER</promise>
    ;;
  impl_requested)
    # 受信メッセージから "implemented: ..." or "codex_failed" を識別
    # codex_failed なら: state.codex_failed_count++ → Step 7(Safety)へ
    # implemented なら: state.codex_failed_count = 0
    # Step 5: bash run-eval.sh → eval-exit.txt 保存
    # SendMessage(to="claude-evaluator-team", summary="iter <N> 評価依頼",
    #   message="iter <N> のゴール達成を評価してください。
    #            .goal-dual/state/evaluations/claude-<N>.json に保存してから
    #            verdict を 1 行で返してください（形式: evaluated: complete|incomplete|regressed）。")
    # Agent(subagent_type="goal-dual-codex-evaluator")  # 使い捨て。同ターン内で完了する想定
    # state.agent_teams_phase = "eval_requested"
    # state.agent_teams_pending_from = ["claude-evaluator-team"]
    # <promise>WAITING_EVALUATOR</promise>
    ;;
  eval_requested)
    # claude-evaluator-team の応答 "evaluated: <verdict>" を確認
    # codex-evaluator の出力（同ターンで取得済み）を確認
    # 合議ルール（メインループ Step 6 と同一）で synthesized verdict を決定
    # synthesized-<ITER>.json 保存 → state.last_synthesized_verdict 更新
    # Step 7: bash safety.sh → STOP_STAGNANT / STOP_HUMAN は即 finalizing
    # Step 8: 判定
    #   complete → Agent(code-reviewer) → commit-iter.sh pass
    #             → state.completed=true, stop_reason="COMPLETE"
    #             → state.agent_teams_phase = "finalizing"
    #   regressed → progress.txt 記録 → state.agent_teams_phase = "iteration_done"
    #   incomplete → commit-iter.sh wip → progress.txt 記録
    #             → state.agent_teams_phase = "iteration_done"
    # <promise>... (次の phase に応じたラベル)</promise>
    ;;
  iteration_done)
    # phase を "init" に戻す
    # jq '.agent_teams_phase = "init" | .agent_teams_pending_from = []' state.json
    # 同ターン内で "init" の処理（dirty check → iter++ → Plan → ...）へ落ちる
    ;;
  finalizing)
    # SendMessage(to="implementer-team", message='{"type":"shutdown_request"}')
    # SendMessage(to="claude-evaluator-team", message='{"type":"shutdown_request"}')
    # state.agent_teams_phase = "shutdown"
    # state.agent_teams_pending_from = ["implementer-team", "claude-evaluator-team"]
    # <promise>WAITING_SHUTDOWN</promise>
    ;;
  shutdown)
    # shutdown_response の受信を確認（implementer-team / claude-evaluator-team の両方）
    # 30 秒タイムアウト後は応答がなくても TeamDelete を強制実行
    # TeamDelete()
    # archive / final-report / generate-pr-description は終了処理セクションで一括実行
    # 最終サマリ出力
    # <promise>COMPLETE</promise>（stop_reason に応じたラベル）
    ;;
esac
```

### 受信メッセージのパース

リーダーが Agent Teams モードで起床した場合、Claude Code は受信メッセージをプロンプト本文に注入する。
リーダーは以下のパターンで発信元と内容を識別する:

| 発信元 | メッセージパターン | 処理 |
|--------|-------------------|------|
| `implementer-team` | `implemented: <files>` | ファイル一覧を取得して eval-cmd へ |
| `implementer-team` | `codex_failed` | codex_failed_count++ → Safety チェック |
| `claude-evaluator-team` | `evaluated: complete\|incomplete\|regressed` | verdict を取得して合議へ |
| いずれのメンバー | `{"type":"shutdown_response",...}` | shutdown カウント（2 つ揃ったら TeamDelete） |
| 不明な形式 | その他 | progress.txt に記録 → 同 phase を維持して SendMessage を再送 |

### メンバー存命チェック（再開時・各 phase 開始前）

`/goal-dual` を再実行した場合、または各 phase 処理の先頭で以下を確認する:

```bash
SNAP_DIR=".goal-dual/state/agents"
STALE_MIN=$(jq -r '.agent_teams_stale_threshold_min // 30' .goal-dual/state.json)
NOW_EPOCH=$(date -u +%s)

for ROLE in implementer claude-evaluator; do
  SNAP_FILE="${SNAP_DIR}/${ROLE}.json"
  if [ -f "$SNAP_FILE" ]; then
    SNAP_AT=$(jq -r '.snapshot_at // ""' "$SNAP_FILE")
    if [ -n "$SNAP_AT" ]; then
      SNAP_EPOCH=$(date -u -d "$SNAP_AT" +%s 2>/dev/null \
                   || date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "$SNAP_AT" +%s 2>/dev/null \
                   || echo 0)
      ELAPSED=$(( (NOW_EPOCH - SNAP_EPOCH) / 60 ))
      if [ "$ELAPSED" -ge "$STALE_MIN" ]; then
        # 停止扱い → 当該メンバーのみ再起動
        echo "[goal-dual] ${ROLE} が ${ELAPSED}分間更新なし。再起動します..."
        Agent(subagent_type="goal-dual-${ROLE}-team",
              team_name="goal-dual",
              name="${ROLE}-team",
              run_in_background=true,
              prompt="goal-dual Agent Teams メンバーとして再起動します。リーダーから SendMessage を待ってください。")
        # 再起動失敗時はフォールバック
      fi
    fi
  fi
done
```

再起動が失敗した場合は以下でフォールバック:

```bash
jq '.agent_teams_mode = false' .goal-dual/state.json > /tmp/state_tmp.json \
  && mv /tmp/state_tmp.json .goal-dual/state.json
AGENT_TEAMS_MODE=false
echo "[$(date)] Agent Teams 再起動失敗。従来モードにフォールバック" >> .goal-dual/progress.txt
```

フォールバック後は「メインループ（while 駆動）」を実行する。

### shutdown 堅牢化

**終了経路ごとの TeamDelete 保証**:

| stop_reason | TeamDelete 経路 |
|-------------|----------------|
| `COMPLETE` | `finalizing` → `shutdown` → TeamDelete |
| `STOP_HUMAN` | Safety から直接 `finalizing` → TeamDelete |
| `STOP_STAGNANT` | Safety から直接 `finalizing` → TeamDelete |
| `STOP_DIRTY` | dirty check から直接 TeamDelete（メンバーへ shutdown_request 不要）|

**shutdown_response タイムアウト**:

`finalizing` フェーズで SendMessage(shutdown_request) を送った後、次ターン（`shutdown` フェーズ）で：

1. 両メンバーから `shutdown_response` を受信した場合 → 即 TeamDelete
2. どちらか / 両方が 30 秒以内に応答しない場合 → `agent_teams_last_msg_at` と現在時刻を比較し、30 秒以上経過していれば強制 TeamDelete

```bash
LAST_MSG_AT=$(jq -r '.agent_teams_last_msg_at // ""' .goal-dual/state.json)
if [ -n "$LAST_MSG_AT" ]; then
  LAST_EPOCH=$(date -u -d "$LAST_MSG_AT" +%s 2>/dev/null \
               || date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "$LAST_MSG_AT" +%s 2>/dev/null \
               || echo 0)
  ELAPSED_SEC=$(( $(date -u +%s) - LAST_EPOCH ))
  if [ "$ELAPSED_SEC" -ge 30 ]; then
    echo "[goal-dual] shutdown_response タイムアウト。強制 TeamDelete します" >> .goal-dual/progress.txt
    TeamDelete()  # 強制終了
  fi
fi
```

### 終了時のクリーンアップ

TeamDelete 後はループを抜ける。archive と最終レポートは終了処理セクションで一括処理する。

---

## 終了処理

ループを抜けたら、まず `final-report.sh` を実行する:

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
bash "$SCRIPTS/final-report.sh"
```

`STOP_STAGNANT` または `STOP_HUMAN` の場合のみ、教訓の提案も生成する:

```bash
STOP_REASON=$(jq -r '.stop_reason // "UNKNOWN"' .goal-dual/state.json)
if [ "$STOP_REASON" = "STOP_STAGNANT" ] || [ "$STOP_REASON" = "STOP_HUMAN" ]; then
  bash "$SCRIPTS/update-project-memory.sh" "$STOP_REASON" || true
fi
```

`COMPLETE` の場合のみ、PR 説明文を生成してからアーカイブする:

```bash
if [ "$STOP_REASON" = "COMPLETE" ]; then
  bash "$SCRIPTS/generate-pr-description.sh" || true
  bash "$SCRIPTS/archive.sh" || true
fi
```

次に、state.json の `stop_reason` に応じて最終サマリを出力する:

**COMPLETE:**

`generate-pr-description.sh` 実行後に state.json から `completed_at` / `review_result` /
`pr_description_path` を Read し、以下のサマリを出力する:

```
=== goal-dual 完了 ===
ゴール達成: <goal_text の先頭 80 文字>
イテレーション数: <N>
ブランチ: <branch>
完了時刻: <state.completed_at>
レビュー結果: <state.review_result>
次のステップ: git push -u origin <branch> && gh pr create
完了レポート: .goal-dual-archive/<タイムスタンプ>-<slug>/state/final-report.md
PR 説明文 : .goal-dual-archive/<タイムスタンプ>-<slug>/state/pr-description.md
           （gh pr create --body-file で利用可能）
```

**STOP_HUMAN:**
```
=== goal-dual 停止: 人間の介入が必要 ===
理由: <stop 理由>
progress.txt と final-review.md を確認してください。
完了レポート: .goal-dual/state/final-report.md
対処後、同じコマンドで再開できます（state は保持されています）。
```

**STOP_STAGNANT:**
```
=== goal-dual 停止: 進捗なし ===
直近 <N> イテレーションで verdict が変わりませんでした。
.goal-dual/state/evaluations/ の最新 synthesized JSON を確認し、
ゴールの再定義または手動での対応を検討してください。
完了レポート: .goal-dual/state/final-report.md
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

1. **ターン内継続（通常モード限定）**: while 駆動ループはターン内で完結させること。中断して「続きは次のターンで」と言ってはならない。
2. **ターン切断（Agent Teams モード限定）**: SendMessage(永続メンバー) の後は必ずターンを切る。`agent_teams_phase` と `agent_teams_pending_from` を state.json に書き込んでからターンを終了すること。
3. **state の読み書き**: 各ステップ後に state.json を更新することで、万が一ターンが切れても再開可能な状態を保つ。
4. **自前判断禁止**: コードレビューや達成判定をサブエージェントに委ねること。main Claude が独自に「これは達成した」と判断してはならない。
5. **git 操作**: commit-iter.sh に任せること。直接 `git commit` しない。
6. **フォールバック禁止（「安全のため」は不可）**: Agent Teams API が例外/エラーを返した場合のみフォールバックする。「応答が遅い」「不明確」などの理由では while モードへ切り替えてはならない。
