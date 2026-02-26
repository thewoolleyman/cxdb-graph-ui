#!/usr/bin/env bash
# Wrapper: delegates to the start-cxdb.sh in the kilroy repo.
# Forces line-buffered stdout/stderr so output appears immediately.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
KILROY_DIR="${KILROY_DIR:-$(cd "$SCRIPT_DIR/../../kilroy" && pwd)}"

# Use non-default ports so this project's CXDB doesn't conflict with others.
export KILROY_CXDB_BINARY_ADDR="${KILROY_CXDB_BINARY_ADDR:-127.0.0.1:9109}"
export KILROY_CXDB_HTTP_BASE_URL="${KILROY_CXDB_HTTP_BASE_URL:-http://127.0.0.1:9110}"
export KILROY_CXDB_UI_ADDR="${KILROY_CXDB_UI_ADDR:-127.0.0.1:9120}"
export KILROY_CXDB_CONTAINER_NAME="${KILROY_CXDB_CONTAINER_NAME:-kilroy-cxdb-graph-ui}"

# stdbuf forces line-buffering so callers see output in real time.
if command -v stdbuf >/dev/null 2>&1; then
  exec stdbuf -oL -eL "$KILROY_DIR/scripts/start-cxdb.sh" "$@"
else
  # macOS may not have stdbuf; script(1) forces a pty which flushes.
  exec script -q /dev/null "$KILROY_DIR/scripts/start-cxdb.sh" "$@"
fi
