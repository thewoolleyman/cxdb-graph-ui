#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SERVER_DIR="${REPO_ROOT}/server"

echo "==> Building cxdb-graph-ui..."
cd "${REPO_ROOT}"
cargo build --release
echo "==> Build complete: ${REPO_ROOT}/target/release/cxdb-graph-ui"
