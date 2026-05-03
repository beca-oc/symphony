#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"
exec ./run-four-repos.local.sh
