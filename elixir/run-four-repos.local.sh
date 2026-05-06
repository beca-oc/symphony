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

start_runner "ai-chatbot" 4001 "workflows/ai-chatbot.md"
start_runner "spice-harvester" 4002 "workflows/spice-harvester.md"
start_runner "causl" 4003 "workflows/causl-io.md"
start_runner "market-ontology" 4004 "workflows/market-ontology.md"

screen -ls || true

cat <<'EOF'

Dashboards:
- ai-chatbot      http://127.0.0.1:4001/
- spice-harvester http://127.0.0.1:4002/
- causl.io        http://127.0.0.1:4003/
- market-ontology http://127.0.0.1:4004/
EOF
