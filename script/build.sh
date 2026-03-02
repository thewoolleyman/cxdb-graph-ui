#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SERVER_DIR="${REPO_ROOT}/server"

echo "==> Building cxdb-graph-ui..."
cd "${SERVER_DIR}"
cargo build --release
echo "==> Build complete: ${SERVER_DIR}/target/release/cxdb-graph-ui"
