#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
UI_DIR="${REPO_ROOT}/ui"

echo "==> Building cxdb-graph-ui..."
cd "${UI_DIR}"
go build -o cxdb-graph-ui .
echo "==> Build complete: ${UI_DIR}/cxdb-graph-ui"
