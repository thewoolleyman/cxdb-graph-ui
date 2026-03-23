#!/usr/bin/env bash
# Open the CXDB web console hosted on the central server via Tailscale.
# Set KILROY_CXDB_HOST in .env to your server's Tailscale hostname.
set -euo pipefail

if [[ -z "${KILROY_CXDB_HOST:-}" ]]; then
  echo "KILROY_CXDB_HOST is not set." >&2
  echo "Add it to .env (e.g. KILROY_CXDB_HOST=your-tailscale-hostname.ts.net)" >&2
  exit 1
fi

CXDB_UI_URL="${KILROY_CXDB_UI_URL:-http://${KILROY_CXDB_HOST}:9120}"

echo "CXDB UI: $CXDB_UI_URL"

if [[ "$(uname)" == "Darwin" ]]; then
  open "$CXDB_UI_URL"
elif command -v xdg-open >/dev/null 2>&1; then
  xdg-open "$CXDB_UI_URL"
fi
