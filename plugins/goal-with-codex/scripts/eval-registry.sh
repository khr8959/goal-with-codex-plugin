#!/bin/bash
# goal-with-codex eval command registry

gwc_allowed_eval_list() {
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

gwc_detect_eval_cmd() {
  EVAL_CMD=""
  EVAL_CMD_SOURCE="none"

  if [ -f package.json ] && jq -e '.scripts.test' package.json >/dev/null 2>&1; then
    EVAL_CMD="npm test"; EVAL_CMD_SOURCE="auto-npm"; return
  fi
  if { [ -f pyproject.toml ] || [ -f pytest.ini ]; } && command -v pytest >/dev/null 2>&1; then
    EVAL_CMD="pytest"; EVAL_CMD_SOURCE="auto-pytest"; return
  fi
  if [ -f go.mod ] && command -v go >/dev/null 2>&1; then
    EVAL_CMD="go test ./..."; EVAL_CMD_SOURCE="auto-go"; return
  fi
  if [ -f Cargo.toml ] && command -v cargo >/dev/null 2>&1; then
    EVAL_CMD="cargo test"; EVAL_CMD_SOURCE="auto-cargo"; return
  fi
  if [ -f pom.xml ]; then
    if [ -x ./mvnw ]; then EVAL_CMD="./mvnw test"; EVAL_CMD_SOURCE="auto-maven"; return; fi
    if command -v mvn >/dev/null 2>&1; then EVAL_CMD="mvn test"; EVAL_CMD_SOURCE="auto-maven"; return; fi
  fi
  if { [ -f build.gradle ] || [ -f build.gradle.kts ]; }; then
    if [ -x ./gradlew ]; then EVAL_CMD="./gradlew test"; EVAL_CMD_SOURCE="auto-gradle"; return; fi
    if command -v gradle >/dev/null 2>&1; then EVAL_CMD="gradle test"; EVAL_CMD_SOURCE="auto-gradle"; return; fi
  fi
  if { compgen -G "*.csproj" >/dev/null 2>&1 || compgen -G "*.sln" >/dev/null 2>&1; } && command -v dotnet >/dev/null 2>&1; then
    EVAL_CMD="dotnet test"; EVAL_CMD_SOURCE="auto-dotnet"; return
  fi
  if [ -f Makefile ] && grep -qE '^test:' Makefile && command -v make >/dev/null 2>&1; then
    EVAL_CMD="make test"; EVAL_CMD_SOURCE="auto-make"; return
  fi
}

gwc_run_with_timeout() {
  if command -v timeout >/dev/null 2>&1; then
    timeout 600 "$@"
  elif command -v gtimeout >/dev/null 2>&1; then
    gtimeout 600 "$@"
  else
    "$@"
  fi
}

gwc_run_allowed_eval() {
  local eval_cmd="$1"
  case "$eval_cmd" in
    "npm test") gwc_run_with_timeout npm test ;;
    "npm run test") gwc_run_with_timeout npm run test ;;
    "pnpm test") gwc_run_with_timeout pnpm test ;;
    "pnpm run test") gwc_run_with_timeout pnpm run test ;;
    "yarn test") gwc_run_with_timeout yarn test ;;
    "bun test") gwc_run_with_timeout bun test ;;
    "pytest") gwc_run_with_timeout pytest ;;
    "python -m pytest") gwc_run_with_timeout python -m pytest ;;
    "python3 -m pytest") gwc_run_with_timeout python3 -m pytest ;;
    "go test ./...") gwc_run_with_timeout go test ./... ;;
    "cargo test") gwc_run_with_timeout cargo test ;;
    "dotnet test") gwc_run_with_timeout dotnet test ;;
    "gradle test") gwc_run_with_timeout gradle test ;;
    "./gradlew test") gwc_run_with_timeout ./gradlew test ;;
    "mvn test") gwc_run_with_timeout mvn test ;;
    "./mvnw test") gwc_run_with_timeout ./mvnw test ;;
    "make test") gwc_run_with_timeout make test ;;
    *)
      echo "eval command is not allowlisted: $eval_cmd"
      gwc_allowed_eval_list | sed 's/^/  - /'
      return 126
      ;;
  esac
}
