#!/usr/bin/env bash
# Stop the remote CXDB instance on the central server.
# Set KILROY_CXDB_HOST in .env to your server's Tailscale hostname.
set -euo pipefail

if [[ -z "${KILROY_CXDB_HOST:-}" ]]; then
  echo "KILROY_CXDB_HOST is not set." >&2
  echo "Add it to .env (e.g. KILROY_CXDB_HOST=your-tailscale-hostname.ts.net)" >&2
  exit 1
fi

echo "The CXDB instance runs on the central server (\$KILROY_CXDB_HOST=$KILROY_CXDB_HOST)."
echo "To stop it, run on the server:"
echo ""
echo "  kilroy cxdb stop cxdb-graph-ui"
echo ""
echo "Or via SSH:"
echo ""
echo "  ssh $KILROY_CXDB_HOST 'kilroy cxdb stop cxdb-graph-ui'"
