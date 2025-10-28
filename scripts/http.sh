#!/usr/bin/env bash
set -euo pipefail

HOST="${1:-10.3.2.11}"
CONNECT_TO="${2:-3}"
MAX_TIME="${3:-5}"

if output=$(curl -fsS --connect-timeout "$CONNECT_TO" --max-time "$MAX_TIME" "http://$HOST" 2>/dev/null); then
  printf '%s\n' "$output"
fi

