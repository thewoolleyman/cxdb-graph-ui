#!/usr/bin/env bash
set -euo pipefail

# Check whether a timeout has been exceeded.
#
# Usage: check_timeout.sh <start_epoch> <timeout_minutes> <label>
#
# Exit codes:
#   0 — still within time limit
#   1 — timeout exceeded
#
# Prints elapsed/remaining info to stdout.

start_epoch="${1:?Usage: check_timeout.sh <start_epoch> <timeout_minutes> <label>}"
timeout_minutes="${2:?Usage: check_timeout.sh <start_epoch> <timeout_minutes> <label>}"
label="${3:-timeout}"

now=$(date +%s)
elapsed_seconds=$(( now - start_epoch ))
elapsed_minutes=$(( elapsed_seconds / 60 ))
limit_seconds=$(( timeout_minutes * 60 ))
remaining_seconds=$(( limit_seconds - elapsed_seconds ))
remaining_minutes=$(( remaining_seconds / 60 ))

if [ "$elapsed_seconds" -ge "$limit_seconds" ]; then
  echo "TIMEOUT: $label exceeded — ${elapsed_minutes}m elapsed, limit was ${timeout_minutes}m"
  exit 1
else
  echo "OK: $label — ${elapsed_minutes}m elapsed, ${remaining_minutes}m remaining (limit ${timeout_minutes}m)"
  exit 0
fi
