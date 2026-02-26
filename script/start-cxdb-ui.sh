#!/usr/bin/env bash
# Wrapper: delegates to start-cxdb-ui.sh in the kilroy repo.
# Forces the UI URL to port 9120 (nginx frontend), not 9110 (raw API).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
KILROY_DIR="${KILROY_DIR:-$(cd "$SCRIPT_DIR/../../kilroy" && pwd)}"

# The kilroy script defaults UI_URL to the bare Rust API port,
# but the actual frontend is served by nginx on port 9120.
export KILROY_CXDB_UI_URL="${KILROY_CXDB_UI_URL:-http://127.0.0.1:9120}"
export KILROY_CXDB_CONTAINER_NAME="${KILROY_CXDB_CONTAINER_NAME:-kilroy-cxdb-graph-ui}"
export KILROY_CXDB_OPEN_UI=1

# stdbuf forces line-buffering so callers see output in real time.
if command -v stdbuf >/dev/null 2>&1; then
  exec stdbuf -oL -eL "$KILROY_DIR/scripts/start-cxdb-ui.sh" "$@"
else
  exec script -q /dev/null "$KILROY_DIR/scripts/start-cxdb-ui.sh" "$@"
fi
