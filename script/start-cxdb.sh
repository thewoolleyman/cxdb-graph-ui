#!/usr/bin/env bash
# Wrapper: delegates to the start-cxdb.sh in the kilroy repo.
# Forces line-buffered stdout/stderr so output appears immediately.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
KILROY_DIR="${KILROY_DIR:-$(cd "$SCRIPT_DIR/../../kilroy" && pwd)}"

# stdbuf forces line-buffering so callers see output in real time.
if command -v stdbuf >/dev/null 2>&1; then
  exec stdbuf -oL -eL "$KILROY_DIR/script/start-cxdb.sh" "$@"
else
  # macOS may not have stdbuf; script(1) forces a pty which flushes.
  exec script -q /dev/null "$KILROY_DIR/script/start-cxdb.sh" "$@"
fi
