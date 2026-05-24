#!/bin/bash
# goal-dual/scripts/init.sh — goal-dual の初期化
# Usage: bash init.sh "<goal-text>"
# 終了コード: 0=成功 / 1=エラー / 2=再開（既存 state あり）
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib.sh"

GOAL_TEXT="$*"
ARG_WAS_EMPTY=false
FROM_PLAN=false
PLAN_DIR=".goal-dual/plan"

if [ -z "$GOAL_TEXT" ]; then
  ARG_WAS_EMPTY=true
  EXISTING_COMPLETED=$(jq -r '.completed // empty' .goal-dual/state.json 2>/dev/null || true)
  EXISTING_ITER=$(jq -r '.iteration // 0' .goal-dual/state.json 2>/dev/null || echo "0")

  if [ "$EXISTING_COMPLETED" = "true" ]; then
    GOAL_TEXT=$(jq -r '.goal_text // "completed"' .goal-dual/state.json 2>/dev/null || echo "completed")
  elif [ "$EXISTING_COMPLETED" = "false" ] && [ "${EXISTING_ITER:-0}" -gt 0 ]; then
    GOAL_TEXT=$(jq -r '.goal_text // "resume"' .goal-dual/state.json 2>/dev/null || echo "resume")
  elif [ ! -f "$PLAN_DIR/status.json" ]; then
    echo "ゴールが指定されておらず、実行可能な plan も見つかりません。" >&2
    echo "直接実行する場合: /goal-dual:run <ゴールテキスト>" >&2
    echo "計画から始める場合: /goal-dual:plan <相談したいゴール> の後に /goal-dual:run" >&2
    exit 1
  else

    PLAN_READY=$(jq -r '.ready_for_execution // false' "$PLAN_DIR/status.json" 2>/dev/null || echo "false")
    if [ "$PLAN_READY" != "true" ]; then
      echo "plan はまだ実行可能ではありません。未解決事項を確認してください:" >&2
      [ -f "$PLAN_DIR/questions.md" ] && cat "$PLAN_DIR/questions.md" >&2
      exit 1
    fi

    if [ ! -f "$PLAN_DIR/goal.md" ]; then
      echo "plan は ready ですが .goal-dual/plan/goal.md が見つかりません。" >&2
      exit 1
    fi

    GOAL_TEXT=$(cat "$PLAN_DIR/goal.md")
    FROM_PLAN=true
  fi
elif [ -f "$PLAN_DIR/status.json" ] && [ ! -f ".goal-dual/state.json" ]; then
  echo ".goal-dual/plan/ が存在するため、引数付きの直接実行は停止します。" >&2
  echo "既存 plan を使う場合は引数なしで /goal-dual:run を実行してください。" >&2
  echo "別の goal を実行する場合は、不要な .goal-dual/plan/ を削除またはアーカイブしてから再実行してください。" >&2
  exit 1
fi

# --- 必須コマンドチェック ---
for cmd in jq node; do
  command -v "$cmd" >/dev/null || { echo "$cmd が必要です" >&2; exit 1; }
done
command -v codex >/dev/null || { echo "codex CLI が必要です: npm install -g @openai/codex" >&2; exit 1; }

# --- CODEX_PLUGIN_ROOT 解決（codex@openai-codex プラグインの root）---
if [ -z "${CODEX_PLUGIN_ROOT:-}" ]; then
  CODEX_PLUGIN_ROOT=$(resolve_codex_plugin_root)
fi
if [ -z "${CODEX_PLUGIN_ROOT:-}" ] || [ ! -f "$CODEX_PLUGIN_ROOT/scripts/codex-companion.mjs" ]; then
  echo "codex@openai-codex プラグインが見つかりません。インストールを確認してください。" >&2
  exit 1
fi
export CODEX_PLUGIN_ROOT

# --- GOAL_DUAL_PLUGIN_ROOT 解決（goal-dual プラグイン自身の root）---
GOAL_DUAL_PLUGIN_ROOT=$(resolve_goal_dual_plugin_root)
export GOAL_DUAL_PLUGIN_ROOT

# --- git 利用可否を自動検出 ---
NO_GIT=true
CURRENT_BRANCH="(no-git)"
BASE_BRANCH=""
BRANCH_AUTO_CREATED=false

if command -v git >/dev/null 2>&1 && git rev-parse --git-dir >/dev/null 2>&1; then
  NO_GIT=false

  # .git/info/exclude に追記（.gitignore を変更すると git status が dirty になり dirty check 誤検知する）
  GIT_EXCLUDE="$(git rev-parse --git-dir)/info/exclude"
  mkdir -p "$(dirname "$GIT_EXCLUDE")"
  for entry in ".goal-dual/" ".goal-dual-archive/"; do
    if ! grep -qxF "$entry" "$GIT_EXCLUDE" 2>/dev/null; then
      printf '\n%s\n' "$entry" >> "$GIT_EXCLUDE"
      echo ".git/info/exclude に $entry を追記しました"
    fi
  done

  # detached HEAD チェック
  CURRENT_BRANCH=$(git branch --show-current)
  if [ -z "$CURRENT_BRANCH" ]; then
    echo "detached HEAD では実行できません" >&2
    exit 1
  fi

  # main/master なら自動でブランチ作成
  if [ "$CURRENT_BRANCH" = "main" ] || [ "$CURRENT_BRANCH" = "master" ]; then
    SLUG=$(python3 -c "
import sys, re
t = sys.argv[1][:50].lower()
t = re.sub(r'[^a-z0-9]+', '-', t)
t = re.sub(r'-+', '-', t).strip('-')
print(t or 'task')
" "$GOAL_TEXT")
    [ -z "$SLUG" ] && SLUG="task-$(date +%s)"
    NEW_BRANCH="goal-dual/$SLUG"
    echo "main/master 上のため、ブランチを自動作成: $NEW_BRANCH"
    git checkout -b "$NEW_BRANCH"
    BRANCH_AUTO_CREATED=true
    CURRENT_BRANCH="$NEW_BRANCH"
  fi

  # base branch 解決
  if git rev-parse --verify origin/main >/dev/null 2>&1; then
    BASE_BRANCH="origin/main"
  elif git rev-parse --verify main >/dev/null 2>&1; then
    BASE_BRANCH="main"
  elif git rev-parse --verify master >/dev/null 2>&1; then
    BASE_BRANCH="master"
  else
    echo "base branch が見つかりません（origin/main / main / master のいずれも不在）" >&2
    exit 1
  fi

  # 起動時 dirty check（lib.sh の goal_dual_dirty_check を使用）
  DIRTY=$(goal_dual_dirty_check)
  if [ -n "$DIRTY" ]; then
    echo "作業ツリーに未コミット変更があります。commit または stash してから再実行してください。" >&2
    echo "$DIRTY" >&2
    exit 1
  fi
else
  echo "git リポジトリが見つかりません。no-git モードで動作します（コミット・差分比較はスキップ）"
fi

# --- 既存 state チェック（再開 or 新規）---
if [ -f ".goal-dual/state.json" ]; then
  COMPLETED=$(jq -r '.completed // false' .goal-dual/state.json 2>/dev/null)
  if [ "$COMPLETED" = "true" ]; then
    echo "前回の goal-dual が完了状態です（stop_reason: $(jq -r '.stop_reason // "不明"' .goal-dual/state.json)）"
    echo "自動アーカイブを試みます..."
    if bash "$SCRIPT_DIR/archive.sh"; then
      echo "アーカイブ完了。新規実行を続行します。"
      if [ "$ARG_WAS_EMPTY" = "true" ] && [ "$FROM_PLAN" != "true" ]; then
        echo "完了済み run をアーカイブしました。新しく実行する goal または plan がないため終了します。" >&2
        exit 1
      fi
    else
      echo "アーカイブに失敗しました。.goal-dual/ を手動で削除してください。" >&2
      exit 1
    fi
    # アーカイブ後は .goal-dual/ が消えているため EXISTING_ITER チェックをスキップ
  else
    EXISTING_ITER=$(jq -r '.iteration // 0' .goal-dual/state.json 2>/dev/null)
    if [ "$EXISTING_ITER" -gt 0 ]; then
      echo "既存の state を検出（iteration: ${EXISTING_ITER}）。前回の続きから再開します。"
      exit 2
    fi
    echo ".goal-dual/state.json が存在するため、既存 run を優先します。"
  fi
fi

# --- eval-cmd 自動検出 ---
EVAL_CMD=""
EVAL_CMD_SOURCE="none"
if [ -f package.json ]; then
  if jq -e '.scripts.test' package.json >/dev/null 2>&1; then
    EVAL_CMD="npm test"
    EVAL_CMD_SOURCE="auto-npm"
    echo "eval-cmd 自動検出: npm test（package.json）"
  fi
elif [ -f pyproject.toml ] || [ -f pytest.ini ]; then
  if command -v pytest >/dev/null 2>&1; then
    EVAL_CMD="pytest"
    EVAL_CMD_SOURCE="auto-pytest"
    echo "eval-cmd 自動検出: pytest"
  fi
fi
[ -z "$EVAL_CMD" ] && echo "eval-cmd: 自動検出できません（AI 判定のみで評価）"

# --- review level ---
REVIEW_LEVEL="${GOAL_DUAL_REVIEW_LEVEL:-standard}"
case "$REVIEW_LEVEL" in
  strict|standard|relaxed) ;;
  *) echo "GOAL_DUAL_REVIEW_LEVEL は strict/standard/relaxed のいずれかを指定してください" >&2; exit 1 ;;
esac

# --- プロジェクト記憶ファイルの検出 ---
PROJECT_MEMORY_PATH=""
if [ -f ".goal-dual-memory.md" ]; then
  PROJECT_MEMORY_PATH="$(pwd)/.goal-dual-memory.md"
  echo "プロジェクト記憶ファイルを検出: .goal-dual-memory.md"
fi

# --- .goal-dual/ ディレクトリ初期化 ---
mkdir -p .goal-dual/state/evaluations .goal-dual/logs

# no-git モードでも全エージェントから一貫して変更ファイルを検出できるように
# .goal-dual/.started マーカーを生成する（find . -newer .goal-dual/.started 用）
touch .goal-dual/.started

# .gitignore（git がある場合のみ意味を持つが、あっても無害）
if [ ! -f .goal-dual/.gitignore ]; then
  cat > .goal-dual/.gitignore <<'EOF'
state/mini-plan.md
state/plan-revised.md
state/eval-output.log
state/eval-exit.txt
state/final-review.md
logs/
.started
EOF
fi

# goal.md
cat > .goal-dual/goal.md <<EOF
# ゴール

${GOAL_TEXT}

---
設定日: $(date)
モード: $([ "$NO_GIT" = "true" ] && echo "no-git" || echo "git（ブランチ: ${CURRENT_BRANCH} / ベース: ${BASE_BRANCH}）")
review-level: ${REVIEW_LEVEL}
EOF

# state.json（config.json は廃止し、こちらに統合）
jq -n \
  --arg goal_text "$GOAL_TEXT" \
  --arg eval_cmd "$EVAL_CMD" \
  --arg eval_cmd_source "$EVAL_CMD_SOURCE" \
  --arg base_branch "$BASE_BRANCH" \
  --arg branch "$CURRENT_BRANCH" \
  --argjson branch_auto_created "$BRANCH_AUTO_CREATED" \
  --argjson no_git "$NO_GIT" \
  --arg review_level "$REVIEW_LEVEL" \
  --arg started_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg codex_plugin_root "$CODEX_PLUGIN_ROOT" \
  --arg goal_dual_plugin_root "$GOAL_DUAL_PLUGIN_ROOT" \
  --arg project_memory_path "$PROJECT_MEMORY_PATH" \
  '{
    goal_text: $goal_text,
    eval_cmd: (if $eval_cmd == "" then null else $eval_cmd end),
    eval_cmd_source: $eval_cmd_source,
    base_branch: (if $base_branch == "" then null else $base_branch end),
    branch: $branch,
    branch_auto_created: $branch_auto_created,
    no_git: $no_git,
    review_level: $review_level,
    iteration: 0,
    started_at: $started_at,
    last_updated_at: $started_at,
    completed: false,
    stop_reason: null,
    consecutive_same_evaluation: 0,
    last_synthesized_verdict: null,
    codex_failed_count: 0,
    scope_allow: [],
    scope_deny: [],
    scope_mode: "advisory",
    task_breakdown_enabled: false,
    current_task_index: 1,
    task_count: 1,
    project_memory_path: (if $project_memory_path == "" then null else $project_memory_path end),
    from_plan: false,
    plan_source: null,
    codex_plugin_root: $codex_plugin_root,
    goal_dual_plugin_root: $goal_dual_plugin_root,
    plugin_root: $codex_plugin_root
  }' > .goal-dual/state.json

if [ "$FROM_PLAN" = "true" ]; then
  jq '.from_plan = true | .plan_source = ".goal-dual/plan"' \
    .goal-dual/state.json > /tmp/state_tmp.json && mv /tmp/state_tmp.json .goal-dual/state.json

  if [ -f "$PLAN_DIR/acceptance-criteria.md" ]; then
    cp "$PLAN_DIR/acceptance-criteria.md" .goal-dual/state/acceptance-criteria.md
  fi
  if [ -f "$PLAN_DIR/scope.md" ]; then
    cp "$PLAN_DIR/scope.md" .goal-dual/state/scope.md
  fi
  jq --arg t "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '.executed = true | .executed_at = $t' \
    "$PLAN_DIR/status.json" > /tmp/plan_status_tmp.json \
    && mv /tmp/plan_status_tmp.json "$PLAN_DIR/status.json"
fi

# progress.txt
cat > .goal-dual/progress.txt <<EOF
# goal-dual Progress Log

Started: $(date)
Mode: $([ "$NO_GIT" = "true" ] && echo "no-git" || echo "git（${CURRENT_BRANCH} → ${BASE_BRANCH}）")
Goal: ${GOAL_TEXT}
eval-cmd: ${EVAL_CMD:-なし}
review-level: ${REVIEW_LEVEL}
---
EOF

echo ""
echo "=== goal-dual 初期化完了 ==="
echo "  ゴール             : $GOAL_TEXT"
if [ "$NO_GIT" = "true" ]; then
  echo "  モード             : no-git（コミット・差分比較はスキップ）"
else
  echo "  ブランチ           : ${CURRENT_BRANCH}（ベース: ${BASE_BRANCH}）"
fi
echo "  eval-cmd           : ${EVAL_CMD:-なし（${EVAL_CMD_SOURCE}）}"
echo "  review             : $REVIEW_LEVEL"
echo "  from-plan          : $FROM_PLAN"
echo "  codex-plugin-root  : $CODEX_PLUGIN_ROOT"
echo "  goal-dual-root     : $GOAL_DUAL_PLUGIN_ROOT"

exit 0
