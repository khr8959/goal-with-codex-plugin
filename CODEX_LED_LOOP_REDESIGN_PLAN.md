# goal-dual Claudeオーケストレータ + Codex活用ループ再設計計画

## 目的

現在の goal-dual は、Claude と Codex の確認工程を毎ループで厚く実行する設計になっている。
品質面では安全だが、軽い変更でもステップ数・待ち時間・トークン消費が大きくなりやすい。

goal-dual は独自のコード実装エンジンではない。
Claude Code から OpenAI Codex プラグインを呼び出し、反復開発ワークフローに組み込むためのオーケストレーション層である。

この再設計では、以下を目指す。

- Claude をオーケストレータとして明確に位置づける
- OpenAI Codex プラグインをコード作業の主担当として最大限活用する
- 1回で完璧に作るのではなく、小さく実装して何度も修正する
- 通常ループを軽量化し、必要な場面だけ Claude の重い確認を使う
- ユーザーが `/goal-dual` を使うべきか判断しやすい導線を追加する

## 基本思想

再設計後の goal-dual は、Claude と Codex を単純に二者分担させるものではない。
Claude がオーケストレータとして全体を制御し、OpenAI Codex プラグインを作業者として呼び分ける。

```text
Claude Code
  ↓
goal-dual plugin
  - ゴール管理
  - state 管理
  - Codex 呼び出し
  - 停止、継続、完了判断
  ↓
OpenAI Codex plugin
  - コード調査
  - 実装
  - テスト失敗の分析
  - 一次評価
```

作業量は Codex に寄せる。
制御権と最終責任は Claude オーケストレータに残す。

## 新しい役割分担

| 役割 | 担当 | 内容 |
|---|---|---|
| オーケストレーション | Claude | state を読み書きし、次にどの工程へ進むか判断する |
| ゴール整理 | Claude | ユーザーの依頼を読み、完了条件と変更範囲を整理する |
| 作業判断 | router | 通常対応か goal-dual 向きかをオーケストレータに提案する |
| 調査 | Codex plugin | 関連ファイル、既存実装、テスト構造を調べる |
| 計画 | Codex plugin | 今回のループで実施する小さな修正方針を決める |
| 実装 | Codex plugin | コードを変更する |
| 自己レビュー | Codex plugin | 変更内容、リスク、次に見るべき点をまとめる |
| テスト | shell | `npm test` / `pytest` などを実行する |
| 一次判定 | Codex plugin | テスト結果と完了条件から、完了候補か未完了かを判定する |
| 最終確認 | Claude | 完了候補、停滞、高リスク時のみ確認する |

## 新しい通常ループ

```text
Phase 0: 初期化
  - git / no-git 検出
  - ブランチ作成
  - eval-cmd 検出
  - .goal-dual/ 作成

Phase 1: Claude によるゴール整理
  - 完了条件を作る
  - 変更してよい範囲、避ける範囲を整理する
  - 必要ならタスク分割する

Loop:
  Step 1: dirty check
  Step 2: Claude Orchestrator が次の作業依頼を組み立てる
  Step 3: Codex Work
    - 調査
    - 小さな計画
    - 実装
    - 自己レビュー
  Step 4: eval-cmd 実行
  Step 5: Codex Judge
    - eval-cmd が失敗した場合は原則 incomplete
    - eval-cmd が成功した場合、完了条件を満たすか判定
  Step 6: Claude Orchestrator が続行、停止、最終確認を判断
    - Codex が complete 候補を出した場合
    - 停滞した場合
    - 高リスク変更の場合
    - Codex が blocked を返した場合
  Step 7: commit / retry / stop
```

## 現在のループから削るもの

### Claude Plan の常時実行をやめる

現在は毎ループで公式 Plan エージェントが調査と計画を担当している。
再設計後は、Claude オーケストレータが作業依頼を組み立て、Codex Work の中で調査・計画・実装をまとめて行う。

変更対象:

- `plugins/goal-dual/commands/goal-dual.md`
- `plugins/goal-dual/agents/goal-dual-implementer.md`
- `plugins/goal-dual/scripts/implement.sh`

作業内容:

- Step 2 の `Agent(subagent_type="Plan")` を通常ループから外す
- `mini-plan.md` 前提を弱める
- Claude が完了条件、前回結果、制約を整理して Codex に渡す
- Codex が自分で調査して実装できるプロンプトへ変更する
- 必要なら `goal-dual-codex-worker.md` と `codex-work.sh` を新規追加する

### Adversarial Review を条件付きにする

現在は毎ループで Codex による計画批判を行っている。
再設計後は、高リスクまたは strict 設定時だけ実行する。

起動条件:

- `GOAL_DUAL_REVIEW_LEVEL=strict`
- 認証、課金、権限、削除、セキュリティに関わる変更
- 変更ファイル数が多い
- 同じ失敗が2回以上続いた
- Codex Work が `risk: high` を返した

変更対象:

- `plugins/goal-dual/commands/goal-dual.md`
- `plugins/goal-dual/agents/goal-dual-adversarial-reviewer.md`
- `plugins/goal-dual/scripts/adversarial-review.sh`

作業内容:

- 毎回実行から条件付き実行に変更する
- スキップ時は `plan-revised.md` なしでも Codex Work が進むようにする
- 実行理由を `.goal-dual/progress.txt` に記録する

### Claude evaluator の毎回起動をやめる

現在は毎ループで Claude evaluator と Codex evaluator を並列実行している。
再設計後は、通常判定を Codex evaluator に寄せる。
Claude evaluator は完了候補、停滞、高リスク時だけ使う。
ただし最終判断は Codex evaluator ではなく Claude オーケストレータが行う。

変更対象:

- `plugins/goal-dual/commands/goal-dual.md`
- `plugins/goal-dual/agents/goal-dual-claude-evaluator.md`
- `plugins/goal-dual/agents/goal-dual-codex-evaluator.md`
- `plugins/goal-dual/scripts/codex-evaluate.sh`

作業内容:

- `eval_exit != 0` の場合は AI 評価を省略して `incomplete` にする
- `eval_exit == 0` の場合はまず Codex evaluator のみ実行する
- Codex が `complete` を返した場合だけ Claude final check を実行する
- Codex が `blocked` または `regressed` を返した場合は Claude オーケストレータ確認へ回す

## 新規追加する機能

### goal-dual-router

ユーザーの依頼が goal-dual 向きかどうかを判断する。
最初は自動起動ではなく、判定用コマンドとして追加する。
router は goal-dual を直接起動する判断者ではなく、Claude オーケストレータの補助役として扱う。

追加候補:

- `plugins/goal-dual/commands/goal-dual-route.md`
- `plugins/goal-dual/agents/goal-dual-router.md`

判定結果の例:

```json
{
  "recommended": true,
  "confidence": 0.82,
  "reason": "複数ファイルの実装とテスト確認が必要になりそうです",
  "risk": "medium",
  "suggested_goal": "ログイン後にユーザー情報を表示できるようにする"
}
```

goal-dual 推奨条件:

- コード変更が必要
- テストや動作確認が必要
- 複数ファイルにまたがりそう
- バグ修正や原因調査が必要
- ユーザーの依頼が抽象的で、何度か修正しながら進める方がよい

goal-dual 非推奨条件:

- 説明だけ
- コードレビューだけ
- コマンド出力の確認だけ
- README の軽い一文修正
- コミットしてほしくない作業
- 仕様確認が先に必要

### Codex Work

OpenAI Codex プラグインに調査、計画、実装、自己レビューをまとめて担当させる。
Claude オーケストレータは、Codex に渡す入力を整理し、Codex の出力を state に反映する。

追加候補:

- `plugins/goal-dual/agents/goal-dual-codex-worker.md`
- `plugins/goal-dual/scripts/codex-work.sh`

Codex Work の出力契約:

```json
{
  "status": "implemented|blocked|no_change",
  "changed_files": ["src/example.ts"],
  "summary": "実装内容の短い説明",
  "self_review": "自分で確認した内容",
  "risk": "low|medium|high",
  "next_action": "次に確認すべきこと"
}
```

実装ルール:

- 1ループでは小さく直す
- 完了条件を常に参照する
- 前回の評価結果とテスト失敗を優先して直す
- 変更禁止範囲には触らない
- 迷ったら `blocked` を返す

### Claude Final Check

Claude の確認を毎回ではなく、必要な場面だけに限定する。
これは独立した作業者というより、オーケストレータによる節目判断である。

追加候補:

- `plugins/goal-dual/agents/goal-dual-final-checker.md`

起動条件:

- Codex evaluator が `complete` を返した
- Codex Work が `blocked` を返した
- Codex Work が `risk: high` を返した
- 同じ失敗が連続した
- 変更ファイル数が多い
- セキュリティ、認証、課金、削除、権限に関わる

判定結果:

```json
{
  "verdict": "complete|incomplete|stop_human",
  "reason": "判断理由",
  "required_action": "次にやること"
}
```

## WIP commit 方針の変更

現在は incomplete でも毎回 WIP commit を作る。
再設計後は、デフォルトでは COMPLETE 時のみ commit する。

環境変数で従来動作を選べるようにする。

| 変数 | 内容 | デフォルト |
|---|---|---|
| `GOAL_DUAL_WIP_COMMITS` | `1` なら incomplete 時も WIP commit する | 未設定 |

変更対象:

- `plugins/goal-dual/commands/goal-dual.md`
- `plugins/goal-dual/scripts/commit-iter.sh`

作業内容:

- incomplete 時は `GOAL_DUAL_WIP_COMMITS=1` の場合だけ `commit-iter.sh wip` を呼ぶ
- WIP commit を作らない場合も `.goal-dual/progress.txt` と state は更新する

## 停止条件の強化

Codex の作業割合を増やすため、同じ失敗を繰り返す危険をオーケストレータ側で検出する。

追加する停止条件:

- 同じ `eval-output.log` の失敗要約が2回続いた
- Codex Work が `blocked` を返した
- Codex Work が3回連続で `no_change` を返した
- 変更ファイル数が急に増えた
- 同じ完了条件が連続で未達
- `risk: high` が出た

変更対象:

- `plugins/goal-dual/scripts/safety.sh`
- `plugins/goal-dual/scripts/lib.sh`
- `plugins/goal-dual/commands/goal-dual.md`

## README の整理方針

README は内部ステップを前面に出しすぎない。
非エンジニアにも伝わる説明にする。

新しい概要:

```text
goal-dual は、Claude Code 上で OpenAI Codex プラグインを反復開発ワークフローに組み込むためのプラグインです。
Claude が全体を進行管理し、Codex がコード調査・実装・一次評価を担当します。
```

ユーザー向けワークフロー:

```text
1. Claude がゴールを整理する
2. goal-dual が OpenAI Codex プラグインへ作業を依頼する
3. Codex がコードを調べて実装する
4. テストを実行する
5. Codex が一次判定し、Claude が続行または完了を判断する
```

詳細な内部構成は下位セクションへ移す。
Agent Teams モードは通常利用から外し、補足扱いにする。

変更対象:

- `README.md`

## 実装フェーズ

### Phase 1: ドキュメントと設計の整理

目的:

- README の見え方を新方針に合わせる
- 実装前に新ループの仕様を固定する

作業:

- README のワークフロー説明を5ステップに整理する
- Claude/Codex の役割分担表を追加する
- Agent Teams の説明を通常利用から分離する
- `goal-dual-route` の位置づけを説明する

完了条件:

- README を読んだ非エンジニアが、何をするプラグインか理解できる
- 内部ステップ数が多く見えすぎない
- Claude オーケストレータ、Codex 作業担当の方針が明記されている

### Phase 2: router の追加

目的:

- `/goal-dual` を使うべきか判断できる導線を作る

作業:

- `goal-dual-router.md` を追加する
- `goal-dual-route.md` コマンドを追加する
- router の JSON 出力契約を定義する
- README に使い方を追加する

完了条件:

- `/goal-dual-route <依頼>` で goal-dual 推奨可否が出る
- 実装やコミットは行わない
- 推奨時は `/goal-dual ...` の候補文を出す

### Phase 3: Codex Work の追加

目的:

- 調査、計画、実装、自己レビューを OpenAI Codex プラグイン呼び出しに統合する

作業:

- `goal-dual-codex-worker.md` を追加する
- `codex-work.sh` を追加する
- `implement.sh` との役割重複を整理する
- `goal-dual.md` の Step 2〜4 を Codex Work 中心に変更する

完了条件:

- Claude Plan なしで Codex plugin が調査から実装まで進められる
- Codex Work の JSON が state に保存される
- 失敗時に `blocked` / `no_change` を扱える

### Phase 4: 評価フローの軽量化

目的:

- 毎回の Claude evaluator 起動をやめる

作業:

- `eval_exit != 0` の場合は即 `incomplete` にする
- `eval_exit == 0` の場合は Codex evaluator を先に実行する
- Codex が `complete` の場合のみ Claude final check を呼ぶ
- Codex が `blocked` / `regressed` の場合は STOP_HUMAN 候補にする

完了条件:

- テスト失敗時に Claude evaluator が起動しない
- 完了候補時だけ Claude final check が起動する
- synthesized JSON の形式は既存互換を保つ

### Phase 5: WIP commit と停止条件の見直し

目的:

- ループを軽くしつつ、暴走を止める

作業:

- `GOAL_DUAL_WIP_COMMITS` を追加する
- incomplete 時の WIP commit をデフォルト無効にする
- `safety.sh` に Codex Work の状態を使った停止条件を追加する
- progress に停止理由を分かりやすく出す

完了条件:

- デフォルトでは COMPLETE 時のみ commit される
- `GOAL_DUAL_WIP_COMMITS=1` で従来型 WIP commit が可能
- 同じ失敗や blocked を検出して STOP_HUMAN にできる

### Phase 6: 互換性確認とテスト

目的:

- Marketplace 経由インストール後も動作することを確認する

作業:

- `claude plugin validate .`
- `claude plugin validate ./plugins/goal-dual`
- `bash -n plugins/goal-dual/scripts/*.sh`
- `/goal-dual-route` の手動確認
- 小さな Node.js テストプロジェクトで `/goal-dual` を実行
- テスト失敗時に軽量ループになることを確認
- COMPLETE 時に final-report / PR description / archive が動くことを確認

完了条件:

- プラグイン検証が通る
- marketplace cache からも script 解決できる
- Claude オーケストレータ + Codex Work で最低1件の実装が完了する
- STOP_HUMAN / STOP_STAGNANT の既存挙動が壊れていない

## 実装時の注意

- 既存の `.goal-dual/state.json` との互換性をできるだけ保つ
- 既存の `COMPLETE` / `STOP_HUMAN` / `STOP_STAGNANT` / `STOP_DIRTY` は維持する
- 最初から Agent Teams モードを再設計しない
- まず通常モードを安定させる
- README では内部スクリプト数を強調しすぎない
- OpenAI Codex プラグインへの作業委譲を増やすほど、出力 JSON の検証を厳しくする

## 推奨する最初のPR範囲

最初のPRでは、すべてを一度に実装しない。
以下までに限定する。

1. README の新方針への整理
2. `/goal-dual-route` と `goal-dual-router` の追加
3. `eval_exit != 0` 時の早期 incomplete
4. Adversarial Review の条件付き実行

Codex Work 統合と WIP commit 方針変更は、次のPRに分ける。
