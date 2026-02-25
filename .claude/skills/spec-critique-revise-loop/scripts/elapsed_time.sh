#!/usr/bin/env bash
set -euo pipefail

# Print elapsed time in MM:SS format from a start epoch.
#
# Usage: elapsed_time.sh <start_epoch>
#
# Output: e.g. "3:07" or "125:30"

start_epoch="${1:?Usage: elapsed_time.sh <start_epoch>}"
now=$(date +%s)
elapsed=$(( now - start_epoch ))
minutes=$(( elapsed / 60 ))
seconds=$(( elapsed % 60 ))
printf "%d:%02d\n" "$minutes" "$seconds"
