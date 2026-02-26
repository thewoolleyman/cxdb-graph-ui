#!/usr/bin/env bash
# Stop the CXDB instance started by start-cxdb.sh.
# Stops the Docker container AND kills any processes on our project's ports.
set -euo pipefail

CONTAINER_NAME="${KILROY_CXDB_CONTAINER_NAME:-kilroy-cxdb-graph-ui}"
BINARY_PORT="${KILROY_CXDB_BINARY_PORT:-9109}"
HTTP_PORT="${KILROY_CXDB_HTTP_PORT:-9110}"

# --- Docker container ---

if command -v docker >/dev/null 2>&1; then
  state="$(docker inspect -f '{{.State.Status}}' "$CONTAINER_NAME" 2>/dev/null || true)"
  case "$state" in
    running)
      docker stop "$CONTAINER_NAME" >/dev/null
      docker rm "$CONTAINER_NAME" >/dev/null 2>&1 || true
      echo "stopped and removed container $CONTAINER_NAME"
      ;;
    "")
      echo "no container named $CONTAINER_NAME"
      ;;
    *)
      docker rm "$CONTAINER_NAME" >/dev/null 2>&1 || true
      echo "removed $state container $CONTAINER_NAME"
      ;;
  esac
else
  echo "docker not found, skipping container check" >&2
fi

# --- Processes listening on our ports ---

kill_port() {
  local port="$1"
  local pids
  pids="$(lsof -ti "tcp:$port" 2>/dev/null || true)"
  if [[ -n "$pids" ]]; then
    echo "killing processes on port $port: $pids"
    echo "$pids" | xargs kill 2>/dev/null || true
  fi
}

kill_port "$BINARY_PORT"
kill_port "$HTTP_PORT"
