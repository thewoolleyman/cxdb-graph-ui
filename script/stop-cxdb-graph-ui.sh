#!/usr/bin/env bash
# Stop the cxdb-graph-ui server started by start-cxdb-graph-ui.sh.
set -euo pipefail

PORT="${PORT:-9030}"

kill_port() {
  local port="$1"
  local pids
  pids="$(lsof -ti "tcp:$port" 2>/dev/null || true)"
  if [[ -n "$pids" ]]; then
    echo "killing processes on port $port: $pids"
    echo "$pids" | xargs kill 2>/dev/null || true
  else
    echo "no processes found on port $port"
  fi
}

kill_port "$PORT"
