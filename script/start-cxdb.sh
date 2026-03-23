#!/usr/bin/env bash
# Verify that the remote CXDB instance is reachable via Tailscale.
# CXDB runs on the central server, managed by `kilroy cxdb start`.
# Set KILROY_CXDB_HOST in .env to your server's Tailscale hostname.
set -euo pipefail

if [[ -z "${KILROY_CXDB_HOST:-}" ]]; then
  echo "KILROY_CXDB_HOST is not set." >&2
  echo "Add it to .env (e.g. KILROY_CXDB_HOST=your-tailscale-hostname.ts.net)" >&2
  exit 1
fi

CXDB_HTTP_BASE_URL="${KILROY_CXDB_HTTP_BASE_URL:-http://${KILROY_CXDB_HOST}:9110}"
CXDB_BINARY_ADDR="${KILROY_CXDB_BINARY_ADDR:-${KILROY_CXDB_HOST}:9109}"
CXDB_UI_URL="${KILROY_CXDB_UI_URL:-http://${KILROY_CXDB_HOST}:9120}"

echo "Checking remote CXDB at $CXDB_HTTP_BASE_URL ..."

if curl -sf -m 5 "$CXDB_HTTP_BASE_URL/healthz" >/dev/null 2>&1; then
  echo "cxdb ready: http=$CXDB_HTTP_BASE_URL binary=$CXDB_BINARY_ADDR ui=$CXDB_UI_URL"
  exit 0
fi

echo "CXDB is not reachable at $CXDB_HTTP_BASE_URL" >&2
echo "" >&2
echo "The CXDB instance runs on the central server (\$KILROY_CXDB_HOST=$KILROY_CXDB_HOST)." >&2
echo "Ensure:" >&2
echo "  1. You are connected to Tailscale" >&2
echo "  2. The CXDB instance is running: ssh $KILROY_CXDB_HOST 'kilroy cxdb status'" >&2
echo "  3. Or start it: ssh $KILROY_CXDB_HOST 'kilroy cxdb start cxdb-graph-ui'" >&2
exit 1
