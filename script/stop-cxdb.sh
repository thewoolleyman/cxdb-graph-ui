#!/usr/bin/env bash
# Stop the CXDB Docker container started by start-cxdb.sh.
set -euo pipefail

CONTAINER_NAME="${KILROY_CXDB_CONTAINER_NAME:-kilroy-cxdb}"

if ! command -v docker >/dev/null 2>&1; then
  echo "docker not found" >&2
  exit 1
fi

state="$(docker inspect -f '{{.State.Status}}' "$CONTAINER_NAME" 2>/dev/null || true)"

case "$state" in
  running)
    docker stop "$CONTAINER_NAME" >/dev/null
    echo "stopped $CONTAINER_NAME"
    ;;
  "")
    echo "no container named $CONTAINER_NAME"
    ;;
  *)
    echo "$CONTAINER_NAME already $state"
    ;;
esac
