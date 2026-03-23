#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
WORKSPACE_DIR="$(dirname "$REPO_ROOT")"

# Clone kilroy fork if it doesn't already exist
KILROY_DIR="$WORKSPACE_DIR/kilroy"
if [ -d "$KILROY_DIR" ]; then
  echo "✓ kilroy repo already exists at $KILROY_DIR"
else
  echo "Cloning kilroy fork …"
  git clone https://github.com/thewoolleyman/kilroy.git "$KILROY_DIR"
fi

# Check Rust toolchain
if command -v cargo &> /dev/null; then
  echo "✓ Rust toolchain available: $(rustc --version)"
else
  echo "✗ Rust toolchain not found — install via https://rustup.rs/"
  exit 1
fi

# Verify KILROY_CXDB_HOST is set
if [[ -z "${KILROY_CXDB_HOST:-}" ]]; then
  echo "✗ KILROY_CXDB_HOST is not set."
  echo "  Add it to .env (e.g. KILROY_CXDB_HOST=your-tailscale-hostname.ts.net)"
  exit 1
fi
echo "✓ KILROY_CXDB_HOST=$KILROY_CXDB_HOST"

# Verify CXDB is reachable on the central server via Tailscale
CXDB_URL="${KILROY_CXDB_HTTP_BASE_URL:-http://${KILROY_CXDB_HOST}:9110}"
echo "Checking remote CXDB at $CXDB_URL ..."
if curl -sf -m 5 "$CXDB_URL/healthz" >/dev/null 2>&1; then
  echo "✓ CXDB is healthy at $CXDB_URL"
else
  echo "✗ CXDB is not reachable at $CXDB_URL"
  echo "  Ensure you are connected to Tailscale and CXDB is running on the server."
  echo "  To start it: ssh \$KILROY_CXDB_HOST 'kilroy cxdb start cxdb-graph-ui'"
  exit 1
fi

# Generate run config with correct CXDB host
