#!/bin/bash
# goal-dual/scripts/init.sh — goal-dual の初期化
# Usage: bash init.sh "<goal-text>"
# 終了コード: 0=成功 / 1=エラー / 2=再開（既存 state あり）
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/eval-registry.sh"

GOAL_TEXT="$*"

if [ -z "$GOAL_TEXT" ]; then
  EXISTING_COMPLETED=$(jq -r '.completed // empty' .goal-dual/state.json 2>/dev/null || true)
  EXISTING_ITER=$(jq -r '.iteration // 0' .goal-dual/state.json 2>/dev/null || echo "0")

  if [ "$EXISTING_COMPLETED" = "false" ] && [ "${EXISTING_ITER:-0}" -gt 0 ]; then
    GOAL_TEXT=$(jq -r '.goal_text // "resume"' .goal-dual/state.json 2>/dev/null || echo "resume")
  else
    echo "ゴールが指定されていません。" >&2
    echo "直接実行する場合: /goal-dual:run <ゴールテキスト>" >&2
    exit 1
  fi
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
  for entry in ".goal-dual/"; do
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

  # /goal-dual は Claude /goal の委譲補助なので、ブランチ作成はユーザーの責務に残す。
  # main/master 上でも停止せず、状態に記録して status/doctor で見えるようにする。
  if [ "$CURRENT_BRANCH" = "main" ] || [ "$CURRENT_BRANCH" = "master" ]; then
    echo "main/master 上で実行します。goal-dual は既定で commit を作成しません。"
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
    echo "前回の goal-dual は完了/停止状態です（stop_reason: $(jq -r '.stop_reason // "不明"' .goal-dual/state.json)）" >&2
    echo "新しいゴールを始める場合は、.goal-dual/ を確認して退避または削除してから /goal-dual:run <ゴール> を実行してください。" >&2
    exit 1
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
goal_dual_detect_eval_cmd
if [ -n "$EVAL_CMD" ]; then
  echo "eval-cmd 自動検出: ${EVAL_CMD}（${EVAL_CMD_SOURCE}）"
else
  echo "eval-cmd: 自動検出できません（評価コマンドはスキップ）"
fi

# --- scope mode（enforce で禁止パス変更を hard block）---
# goal-dual は「危ない時に止まる」ことを価値にするため、既定は enforce。
SCOPE_MODE="${GOAL_DUAL_SCOPE_MODE:-enforce}"
case "$SCOPE_MODE" in
  advisory|enforce) ;;
  *) echo "GOAL_DUAL_SCOPE_MODE は advisory/enforce のいずれかを指定してください" >&2; exit 1 ;;
esac

# --- .goal-dual/ ディレクトリ初期化 ---
mkdir -p .goal-dual/state/evaluations .goal-dual/logs
goal_dual_event "run_initialized" "$(jq -nc \
  --arg mode "$([ "$NO_GIT" = "true" ] && echo "no-git" || echo "git")" \
  --arg branch "$CURRENT_BRANCH" \
  --arg scope_mode "$SCOPE_MODE" \
  '{mode:$mode,branch:$branch,scope_mode:$scope_mode}')"

# no-git モードでも全エージェントから一貫して変更ファイルを検出できるように
# .goal-dual/.started マーカーを生成する（find . -newer .goal-dual/.started 用）
touch .goal-dual/.started

# .gitignore（git がある場合のみ意味を持つが、あっても無害）
if [ ! -f .goal-dual/.gitignore ]; then
  cat > .goal-dual/.gitignore <<'EOF'
state/eval-output.log
state/eval-exit.txt
state/evidence-latest.json
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
  --arg scope_mode "$SCOPE_MODE" \
  --arg started_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg codex_plugin_root "$CODEX_PLUGIN_ROOT" \
  --arg goal_dual_plugin_root "$GOAL_DUAL_PLUGIN_ROOT" \
  '{
    goal_text: $goal_text,
    eval_cmd: (if $eval_cmd == "" then null else $eval_cmd end),
    eval_cmd_source: $eval_cmd_source,
    base_branch: (if $base_branch == "" then null else $base_branch end),
    branch: $branch,
    branch_auto_created: $branch_auto_created,
    no_git: $no_git,
    iteration: 0,
    started_at: $started_at,
    last_updated_at: $started_at,
    completed: false,
    stop_reason: null,
    loop_phase: "iterating",
    scope_allow: [],
    scope_deny: [],
    scope_mode: $scope_mode,
    codex_plugin_root: $codex_plugin_root,
    goal_dual_plugin_root: $goal_dual_plugin_root,
    plugin_root: $codex_plugin_root
  }' > .goal-dual/state.json

# progress.txt
cat > .goal-dual/progress.txt <<EOF
# goal-dual Progress Log

Started: $(date)
Mode: $([ "$NO_GIT" = "true" ] && echo "no-git" || echo "git（${CURRENT_BRANCH} → ${BASE_BRANCH}）")
Goal: ${GOAL_TEXT}
eval-cmd: ${EVAL_CMD:-なし}
scope-mode: ${SCOPE_MODE}
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
echo "  scope-mode         : $SCOPE_MODE"
echo "  codex-plugin-root  : $CODEX_PLUGIN_ROOT"
echo "  goal-dual-root     : $GOAL_DUAL_PLUGIN_ROOT"

exit 0
