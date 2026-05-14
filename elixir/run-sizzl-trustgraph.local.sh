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

while IFS= read -r session; do
  [[ -n "$session" ]] && screen -S "$session" -X quit || true
done < <(screen -ls | awk '$1 ~ "^[0-9]+[.]symphony-sizzl-trustgraph$" { print $1 }')

while IFS= read -r pid; do
  [[ -n "$pid" ]] && kill "$pid" || true
done < <(lsof -tiTCP:4010 -sTCP:LISTEN 2>/dev/null || true)

sleep 1

screen -dmS "symphony-sizzl-trustgraph" /bin/zsh -lc \
  "cd '$PWD' && exec mise exec -- ./bin/symphony $ACK --logs-root './log/sizzl-trustgraph' --port 4010 'workflows/sizzl-trustgraph.md'"

screen -ls || true

cat <<'EOF'

Dashboard:
- sizzl-trustgraph http://127.0.0.1:4010/
EOF
