#!/bin/bash
# goal-dual/scripts/init.sh — goal-dual の初期化
# Usage: bash init.sh "<goal-text>"
# 終了コード: 0=成功 / 1=エラー / 2=再開（既存 state あり）
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib.sh"

GOAL_TEXT="$*"
if [ -z "$GOAL_TEXT" ]; then
  echo "ゴールを指定してください: bash init.sh '<goal-text>'" >&2
  exit 1
fi

# --- 必須コマンドチェック ---
for cmd in jq node; do
  command -v "$cmd" >/dev/null || { echo "$cmd が必要です" >&2; exit 1; }
done
command -v codex >/dev/null || { echo "codex CLI が必要です: npm install -g @openai/codex" >&2; exit 1; }

# --- CLAUDE_PLUGIN_ROOT 解決（lib.sh の resolve_plugin_root を使用）---
if [ -z "${CLAUDE_PLUGIN_ROOT:-}" ]; then
  CLAUDE_PLUGIN_ROOT=$(resolve_plugin_root)
fi
if [ -z "${CLAUDE_PLUGIN_ROOT:-}" ] || [ ! -f "$CLAUDE_PLUGIN_ROOT/scripts/codex-companion.mjs" ]; then
  echo "codex@openai-codex プラグインが見つかりません。インストールを確認してください。" >&2
  exit 1
fi
export CLAUDE_PLUGIN_ROOT

# --- git 利用可否を自動検出 ---
NO_GIT=true
CURRENT_BRANCH="(no-git)"
BASE_BRANCH=""
BRANCH_AUTO_CREATED=false

if command -v git >/dev/null 2>&1 && git rev-parse --git-dir >/dev/null 2>&1; then
  NO_GIT=false

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

# --- Agent Teams モード検出 ---
AGENT_TEAMS_MODE=false
if [ "${CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS:-}" = "1" ]; then
  AGENT_TEAMS_MODE=true
  echo "Agent Teams モード: 有効（CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1）"
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
  --argjson agent_teams_mode "$AGENT_TEAMS_MODE" \
  --arg started_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg plugin_root "$CLAUDE_PLUGIN_ROOT" \
  '{
    goal_text: $goal_text,
    eval_cmd: (if $eval_cmd == "" then null else $eval_cmd end),
    eval_cmd_source: $eval_cmd_source,
    base_branch: (if $base_branch == "" then null else $base_branch end),
    branch: $branch,
    branch_auto_created: $branch_auto_created,
    no_git: $no_git,
    review_level: $review_level,
    agent_teams_mode: $agent_teams_mode,
    iteration: 0,
    started_at: $started_at,
    last_updated_at: $started_at,
    completed: false,
    stop_reason: null,
    consecutive_same_evaluation: 0,
    last_synthesized_verdict: null,
    codex_failed_count: 0,
    plugin_root: $plugin_root,
    agent_teams_phase: "init",
    agent_teams_pending_from: [],
    agent_teams_last_msg_iter: 0,
    agent_teams_last_msg_at: null,
    agent_teams_stale_threshold_min: 30
  }' > .goal-dual/state.json

# progress.txt
cat > .goal-dual/progress.txt <<EOF
# goal-dual Progress Log

Started: $(date)
Mode: $([ "$NO_GIT" = "true" ] && echo "no-git" || echo "git（${CURRENT_BRANCH} → ${BASE_BRANCH}）")
Goal: ${GOAL_TEXT}
eval-cmd: ${EVAL_CMD:-なし}
review-level: ${REVIEW_LEVEL}
agent-teams: ${AGENT_TEAMS_MODE}
---
EOF

echo ""
echo "=== goal-dual 初期化完了 ==="
echo "  ゴール       : $GOAL_TEXT"
if [ "$NO_GIT" = "true" ]; then
  echo "  モード       : no-git（コミット・差分比較はスキップ）"
else
  echo "  ブランチ     : ${CURRENT_BRANCH}（ベース: ${BASE_BRANCH}）"
fi
echo "  eval-cmd     : ${EVAL_CMD:-なし（${EVAL_CMD_SOURCE}）}"
echo "  review       : $REVIEW_LEVEL"
echo "  agent-teams  : $AGENT_TEAMS_MODE"
echo "  plugin       : $CLAUDE_PLUGIN_ROOT"

if [ "$AGENT_TEAMS_MODE" = "true" ]; then
  # TeammateIdle フックスクリプトをプロジェクトにコピーする
  # （CLAUDE_PROJECT_DIR 相対パスで参照できるようにするため）
  mkdir -p .goal-dual/hooks
  if [ -f "$CLAUDE_PLUGIN_ROOT/scripts/teammate-idle-hook.sh" ]; then
    cp "$CLAUDE_PLUGIN_ROOT/scripts/teammate-idle-hook.sh" .goal-dual/hooks/
    chmod +x .goal-dual/hooks/teammate-idle-hook.sh
    echo "TeammateIdle フックを .goal-dual/hooks/ にコピーしました。"
  fi

  cat <<'EOF'

=== Agent Teams モードを使用する場合の注意 ===
本機能は実験的で、Claude Code の Agent Teams API が必要です。

【マルチターン設計】
goal-dual Agent Teams モードは「1 ターン 1 フェーズ」のマルチターン設計です。
SendMessage 後はターンが切れ、チームメンバーの応答は次のターンに配信されます。
メンバーが応答を返さず idle 入りするのを防ぐため、TeammateIdle フックの設定を推奨します。

【TeammateIdle フックの設定方法】
.claude/settings.json に以下を追加してください（プラグインは自動注入しません）:

  "hooks": {
    "TeammateIdle": [{
      "matcher": ".*",
      "hooks": [{
        "type": "command",
        "command": "bash $CLAUDE_PROJECT_DIR/.goal-dual/hooks/teammate-idle-hook.sh"
      }]
    }]
  }

起動失敗時はオーケストレーターが自動的に従来の while ループへフォールバックします。
EOF
fi

exit 0
