#!/bin/bash
# goal-dual/scripts/eval-registry.sh — eval command の検出・実行定義を一元管理する

goal_dual_allowed_eval_list() {
  cat <<'EOF'
npm test
npm run test
pnpm test
pnpm run test
yarn test
bun test
pytest
python -m pytest
python3 -m pytest
go test ./...
cargo test
dotnet test
gradle test
./gradlew test
mvn test
./mvnw test
make test
EOF
}

goal_dual_detect_eval_cmd() {
  EVAL_CMD=""
  EVAL_CMD_SOURCE="none"

  if [ -z "$EVAL_CMD" ] && [ -f package.json ]; then
    if jq -e '.scripts.test' package.json >/dev/null 2>&1; then
      EVAL_CMD="npm test"
      EVAL_CMD_SOURCE="auto-npm"
      return
    fi
  fi

  if [ -z "$EVAL_CMD" ] && { [ -f pyproject.toml ] || [ -f pytest.ini ]; }; then
    if command -v pytest >/dev/null 2>&1; then
      EVAL_CMD="pytest"
      EVAL_CMD_SOURCE="auto-pytest"
      return
    fi
  fi

  if [ -z "$EVAL_CMD" ] && [ -f go.mod ]; then
    if command -v go >/dev/null 2>&1; then
      EVAL_CMD="go test ./..."
      EVAL_CMD_SOURCE="auto-go"
      return
    fi
  fi

  if [ -z "$EVAL_CMD" ] && [ -f Cargo.toml ]; then
    if command -v cargo >/dev/null 2>&1; then
      EVAL_CMD="cargo test"
      EVAL_CMD_SOURCE="auto-cargo"
      return
    fi
  fi

  if [ -z "$EVAL_CMD" ] && [ -f pom.xml ]; then
    if [ -x ./mvnw ]; then
      EVAL_CMD="./mvnw test"
      EVAL_CMD_SOURCE="auto-maven"
      return
    elif command -v mvn >/dev/null 2>&1; then
      EVAL_CMD="mvn test"
      EVAL_CMD_SOURCE="auto-maven"
      return
    fi
  fi

  if [ -z "$EVAL_CMD" ] && { [ -f build.gradle ] || [ -f build.gradle.kts ]; }; then
    if [ -x ./gradlew ]; then
      EVAL_CMD="./gradlew test"
      EVAL_CMD_SOURCE="auto-gradle"
      return
    elif command -v gradle >/dev/null 2>&1; then
      EVAL_CMD="gradle test"
      EVAL_CMD_SOURCE="auto-gradle"
      return
    fi
  fi

  if [ -z "$EVAL_CMD" ] && { compgen -G "*.csproj" >/dev/null 2>&1 || compgen -G "*.sln" >/dev/null 2>&1; }; then
    if command -v dotnet >/dev/null 2>&1; then
      EVAL_CMD="dotnet test"
      EVAL_CMD_SOURCE="auto-dotnet"
      return
    fi
  fi

  if [ -z "$EVAL_CMD" ] && [ -f Makefile ] && grep -qE '^test:' Makefile; then
    if command -v make >/dev/null 2>&1; then
      EVAL_CMD="make test"
      EVAL_CMD_SOURCE="auto-make"
      return
    fi
  fi
}

goal_dual_run_with_timeout() {
  if command -v timeout >/dev/null 2>&1; then
    timeout 600 "$@"
  elif command -v gtimeout >/dev/null 2>&1; then
    gtimeout 600 "$@"
  else
    "$@"
  fi
}

goal_dual_run_allowed_eval() {
  local eval_cmd="$1"
  case "$eval_cmd" in
    "npm test") goal_dual_run_with_timeout npm test ;;
    "npm run test") goal_dual_run_with_timeout npm run test ;;
    "pnpm test") goal_dual_run_with_timeout pnpm test ;;
    "pnpm run test") goal_dual_run_with_timeout pnpm run test ;;
    "yarn test") goal_dual_run_with_timeout yarn test ;;
    "bun test") goal_dual_run_with_timeout bun test ;;
    "pytest") goal_dual_run_with_timeout pytest ;;
    "python -m pytest") goal_dual_run_with_timeout python -m pytest ;;
    "python3 -m pytest") goal_dual_run_with_timeout python3 -m pytest ;;
    "go test ./...") goal_dual_run_with_timeout go test ./... ;;
    "cargo test") goal_dual_run_with_timeout cargo test ;;
    "dotnet test") goal_dual_run_with_timeout dotnet test ;;
    "gradle test") goal_dual_run_with_timeout gradle test ;;
    "./gradlew test") goal_dual_run_with_timeout ./gradlew test ;;
    "mvn test") goal_dual_run_with_timeout mvn test ;;
    "./mvnw test") goal_dual_run_with_timeout ./mvnw test ;;
    "make test") goal_dual_run_with_timeout make test ;;
    *)
      echo "eval-cmd は許可されていないため実行しませんでした: $eval_cmd"
      echo "許可されるコマンド:"
      goal_dual_allowed_eval_list | sed 's/^/  - /'
      return 126
      ;;
  esac
}
