#!/usr/bin/env bash
set -euo pipefail

# Exit condition checker for the critique-revise loop.
#
# Usage: check_exit.sh <critique_file> <exit_criteria> [prev_issues_file]
#
# Exit codes:
#   0 = continue looping
#   1 = converged (exit condition met)
#   2 = stuck (same or subset of previous issues)
#
# Side effects:
#   - Writes sorted current issue titles to <prev_issues_file> (for next round)
#   - Prints status message to stdout

critique_file="$1"
exit_criteria="${2:-no_major_issues_found}"
prev_issues_file="${3:-}"

if [ ! -f "$critique_file" ]; then
  echo "ERROR: critique file not found: $critique_file"
  exit 3
fi

# Extract issue titles: lines matching "## Issue #N: Title"
current_issues_file=$(mktemp)
trap 'rm -f "$current_issues_file"' EXIT

grep -E '^## Issue #[0-9]+:' "$critique_file" \
  | sed 's/^## Issue #[0-9]*: //' \
  | sort \
  > "$current_issues_file" || true

issue_count=$(wc -l < "$current_issues_file" | tr -d ' ')

# --- No issues at all → converged ---
if [ "$issue_count" -eq 0 ]; then
  echo "CONVERGED: no issues found"
  exit 1
fi

# --- no_major_issues_found: check if ALL issues are minor ---
if [ "$exit_criteria" = "no_major_issues_found" ]; then
  # For each issue section, check if it contains minor keywords.
  # An issue section spans from "## Issue #N:" to the next "## " heading or EOF.
  # If ANY section lacks minor keywords, we have a major issue.
  major_count=$(awk '
    /^## Issue #[0-9]+:/ {
      if (section_text != "") {
        if (section_text !~ /[Mm]inor|[Nn]itpick|[Cc]osmetic|[Tt]rivial|[Oo]ptional/) {
          major++
        }
      }
      section_text = $0
      next
    }
    /^## [^I]/ || /^---$/ {
      if (section_text != "") {
        if (section_text !~ /[Mm]inor|[Nn]itpick|[Cc]osmetic|[Tt]rivial|[Oo]ptional/) {
          major++
        }
      }
      section_text = ""
      next
    }
    section_text != "" { section_text = section_text "\n" $0 }
    END {
      if (section_text != "") {
        if (section_text !~ /[Mm]inor|[Nn]itpick|[Cc]osmetic|[Tt]rivial|[Oo]ptional/) {
          major++
        }
      }
      print major + 0
    }
  ' "$critique_file")

  if [ "$major_count" -eq 0 ]; then
    echo "CONVERGED: all $issue_count issue(s) are minor/cosmetic"
    exit 1
  fi
fi

# --- Stuck detection: current issues are a subset of previous round ---
if [ -n "$prev_issues_file" ] && [ -f "$prev_issues_file" ]; then
  # comm -23 outputs lines in current but NOT in previous.
  # If empty, current is a subset of (or equal to) previous → stuck.
  new_issues=$(comm -23 "$current_issues_file" "$prev_issues_file" || true)
  if [ -z "$new_issues" ]; then
    echo "STUCK: current issues are a subset of previous round ($issue_count issue(s))"
    exit 2
  fi
fi

# --- Continue: save current issues for next round comparison ---
if [ -n "$prev_issues_file" ]; then
  cp "$current_issues_file" "$prev_issues_file"
fi

echo "CONTINUE: $issue_count issue(s) found, proceeding to revise"
exit 0
