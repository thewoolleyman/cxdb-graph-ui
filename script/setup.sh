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

# Clone cxdb repo (needed to build the Docker image kilroy expects)
CXDB_DIR="${CXDB_DIR:-$WORKSPACE_DIR/cxdb}"
CXDB_IMAGE="${KILROY_CXDB_IMAGE:-cxdb/cxdb:local}"

if [ -d "$CXDB_DIR" ]; then
  echo "✓ cxdb repo already exists at $CXDB_DIR"
else
  echo "Cloning strongdm/cxdb into $CXDB_DIR …"
  git clone https://github.com/strongdm/cxdb.git "$CXDB_DIR"
fi

# Build CXDB Docker image
if docker image inspect "$CXDB_IMAGE" >/dev/null 2>&1; then
  echo "✓ Docker image $CXDB_IMAGE already exists"
  if [[ "${1:-}" == "--rebuild-cxdb" ]]; then
    echo "Rebuilding as requested …"
  else
    exit 0
  fi
fi

echo "Building $CXDB_IMAGE from $CXDB_DIR (this takes a few minutes) …"
docker build -t "$CXDB_IMAGE" "$CXDB_DIR"
echo "✓ Docker image $CXDB_IMAGE built successfully"
