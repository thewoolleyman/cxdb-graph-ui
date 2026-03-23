#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BINARY="${REPO_ROOT}/target/release/cxdb-graph-ui"
PORT="${PORT:-9030}"

if [[ -z "${KILROY_CXDB_HOST:-}" ]]; then
  echo "KILROY_CXDB_HOST is not set." >&2
  echo "Add it to .env (e.g. KILROY_CXDB_HOST=your-tailscale-hostname.ts.net)" >&2
  exit 1
fi

CXDB_URL="${KILROY_CXDB_HTTP_BASE_URL:-http://${KILROY_CXDB_HOST}:9110}"

"${REPO_ROOT}/script/build.sh"

echo "==> Starting server on port ${PORT}..."
DOT_FLAGS=()
for f in "${REPO_ROOT}"/*.dot; do
  [ -f "$f" ] && DOT_FLAGS+=(--dot "$f")
done

if [ "${#DOT_FLAGS[@]}" -eq 0 ]; then
  echo "Warning: no .dot files found in repo root — server will require --dot flags passed manually."
fi

"${BINARY}" --port "${PORT}" --cxdb "${CXDB_URL}" "${DOT_FLAGS[@]+"${DOT_FLAGS[@]}"}" &
SERVER_PID=$!

if [[ "$(uname)" == "Darwin" ]]; then
  sleep 0.5
  open "http://127.0.0.1:${PORT}"
fi

wait "${SERVER_PID}"
