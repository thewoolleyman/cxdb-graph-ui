#!/usr/bin/env bash
set -euo pipefail

# Parse acknowledgement file(s) and print a round summary.
#
# Usage: round_summary.sh <ack_file> [<ack_file2> ...]
#
# Output format:
#   ✓ Issue #1: Title — applied
#   ~ Issue #2: Title — partial: reason
#   ✗ Issue #3: Title — skipped: reason
#   Issues: 3 | Applied: 1 | Partial: 1 | Skipped: 1

if [ $# -eq 0 ]; then
  echo "Usage: round_summary.sh <ack_file> [<ack_file2> ...]"
  exit 1
fi

# Use awk to parse issue headings and their status lines across all files.
# The acknowledgement format is:
#   ## Issue #N: Title
#   **Status: Applied to specification**
#   or
#   **Status: Partially addressed**
#   or
#   **Status: Not addressed**
awk '
  /^## Issue #[0-9]+:/ {
    # Extract "Issue #N: Title"
    title = $0
    sub(/^## /, "", title)
    pending_title = title
    next
  }

  pending_title != "" && /^\*\*Status:/ {
    status_line = $0
    gsub(/\*\*/, "", status_line)
    sub(/^Status: */, "", status_line)

    if (status_line ~ /[Aa]pplied/) {
      symbol = "✓"
      applied++
    } else if (status_line ~ /[Pp]artial/) {
      symbol = "~"
      partial++
    } else {
      symbol = "✗"
      skipped++
    }
    total++

    # Clean up the status for display
    display_status = status_line
    gsub(/^ +| +$/, "", display_status)

    printf "  %s %s — %s\n", symbol, pending_title, tolower(display_status)
    pending_title = ""
    next
  }
' "$@"

# Print totals using a second pass (simpler than tracking in awk + printing after)
awk '
  /^\*\*Status:/ {
    status_line = $0
    gsub(/\*\*/, "", status_line)
    if (status_line ~ /[Aa]pplied/ && status_line !~ /[Pp]artial/) applied++
    else if (status_line ~ /[Pp]artial/) partial++
    else skipped++
    total++
  }
  END {
    printf "  Issues: %d | Applied: %d | Partial: %d | Skipped: %d\n", total, applied+0, partial+0, skipped+0
  }
' "$@"
