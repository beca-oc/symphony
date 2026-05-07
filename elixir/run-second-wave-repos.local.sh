#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

source_env() {
  local env_file="$1"
  if [[ -f "$env_file" ]]; then
    set -a
    # shellcheck disable=SC1090
    . "$env_file"
    set +a
  fi
}

source_env ../.env
source_env ./.env

node ../scripts/symphony/validate_workflows.mjs

if [[ "${1:-}" == "--dry-run" ]]; then
  exit 0
fi

mise exec -- mix build

ACK="--i-understand-that-this-will-be-running-without-the-usual-guardrails"

start_runner() {
  local name="$1"
  local port="$2"
  local workflow="$3"

  while IFS= read -r session; do
    [[ -n "$session" ]] && screen -S "$session" -X quit || true
  done < <(screen -ls | awk -v name="symphony-${name}" '$1 ~ ("^[0-9]+[.]" name "$") { print $1 }')

  while IFS= read -r pid; do
    [[ -n "$pid" ]] && kill "$pid" || true
  done < <(lsof -tiTCP:"$port" -sTCP:LISTEN 2>/dev/null || true)

  sleep 1

  screen -dmS "symphony-${name}" /bin/zsh -lc \
    "cd '$PWD' && exec mise exec -- ./bin/symphony $ACK --logs-root './log/${name}' --port '${port}' '${workflow}'"
}

start_runner "design-system" 4005 "workflows/design-system.md"
start_runner "causalactions" 4006 "workflows/causalactions.md"
start_runner "causalflow" 4007 "workflows/causalflow.md"
start_runner "causalintelligence" 4008 "workflows/causalintelligence.md"
start_runner "johnny-5-rebuild" 4009 "workflows/johnny-5-rebuild.md"

screen -ls || true

cat <<'EOF'

Dashboards:
- design-system      http://127.0.0.1:4005/
- causalactions      http://127.0.0.1:4006/
- causalflow         http://127.0.0.1:4007/
- causalintelligence http://127.0.0.1:4008/
- johnny-5-rebuild   http://127.0.0.1:4009/
EOF
