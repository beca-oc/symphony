#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

if [[ -f ../.env ]]; then
  set -a
  # shellcheck disable=SC1091
  . ../.env
  set +a
fi

export PATH="/Users/aviyashchin/.asdf/installs/erlang/28.1.1/bin:/Users/aviyashchin/.asdf/installs/elixir/1.19.1-otp-28/bin:$PATH"

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
    "cd '$PWD' && exec ./bin/symphony $ACK --logs-root './log/${name}' --port '${port}' '${workflow}'"
}

start_runner "ai-chatbot" 4001 "workflows/ai-chatbot.md"
start_runner "spice-harvester" 4002 "WORKFLOW.spice-harvester.md"
start_runner "causl" 4003 "WORKFLOW.causl.md"
start_runner "market-ontology" 4004 "WORKFLOW.market-ontology.md"

screen -ls || true
