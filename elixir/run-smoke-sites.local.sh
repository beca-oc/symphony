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

mkdir -p "$HOME/.symphony/worker-home" "$HOME/.symphony/codex-home"

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

start_runner "causl" 4003 "workflows/causl-io.md"
start_runner "website" 4011 "workflows/website.md"
start_runner "causalactions" 4007 "workflows/causalactions.md"
start_runner "causalflow" 4008 "workflows/causalflow.md"
start_runner "causalintelligence" 4009 "workflows/causalintelligence.md"

screen -ls || true

cat <<'EOF'

Dashboards:
- causl.io            http://127.0.0.1:4003/
- subconscious.ai     http://127.0.0.1:4011/
- causalactions       http://127.0.0.1:4007/
- causalflow          http://127.0.0.1:4008/
- causalintelligence  http://127.0.0.1:4009/
EOF
