#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
UI_DIR="${REPO_ROOT}/ui"
BINARY="${UI_DIR}/cxdb-graph-ui"
PORT="${PORT:-9030}"

"${REPO_ROOT}/script/build.sh"

echo "==> Starting server on port ${PORT}..."
DOT_FLAGS=()
for f in "${REPO_ROOT}"/*.dot; do
  [ -f "$f" ] && DOT_FLAGS+=(--dot "$f")
done

if [ "${#DOT_FLAGS[@]}" -eq 0 ]; then
  echo "Warning: no .dot files found in repo root — server will require --dot flags passed manually."
fi

"${BINARY}" --port "${PORT}" "${DOT_FLAGS[@]+"${DOT_FLAGS[@]}"}" &
SERVER_PID=$!

if [[ "$(uname)" == "Darwin" ]]; then
  sleep 0.5
  open "http://127.0.0.1:${PORT}"
fi

wait "${SERVER_PID}"
