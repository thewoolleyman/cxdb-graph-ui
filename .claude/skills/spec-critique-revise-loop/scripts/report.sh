#!/usr/bin/env bash
set -euo pipefail

# Print the final report for the critique-revise loop.
#
# Usage: report.sh --state-dir <dir> --rounds-completed <N> --exit-reason <reason> --exit-criteria <criteria>

state_dir=""
rounds_completed=""
exit_reason=""
exit_criteria=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --state-dir)          state_dir="$2"; shift 2 ;;
    --rounds-completed)   rounds_completed="$2"; shift 2 ;;
    --exit-reason)        exit_reason="$2"; shift 2 ;;
    --exit-criteria)      exit_criteria="$2"; shift 2 ;;
    *) shift ;;
  esac
done

if [ -z "$state_dir" ] || [ -z "$rounds_completed" ] || [ -z "$exit_reason" ]; then
  echo "ERROR: --state-dir, --rounds-completed, and --exit-reason are required"
  exit 1
fi

# Read cumulative counts
cumulative_issues=0
cumulative_applied=0
cumulative_partial=0
cumulative_skipped=0
if [ -f "$state_dir/cumulative" ]; then
  read -r cumulative_issues cumulative_applied cumulative_partial cumulative_skipped < "$state_dir/cumulative"
fi

echo ""
echo "============================================"
echo "  FINAL REPORT"
echo "============================================"
echo "Rounds completed:  $rounds_completed"
echo "Exit reason:       $exit_reason"
echo "Exit criteria:     ${exit_criteria:-(unknown)}"

# Print elapsed time if loop_start exists
if [ -f "$state_dir/loop_start" ]; then
  loop_start=$(cat "$state_dir/loop_start")
  now=$(date +%s)
  elapsed=$(( now - loop_start ))
  elapsed_m=$(( elapsed / 60 ))
  elapsed_s=$(( elapsed % 60 ))
  echo "Elapsed time:      ${elapsed_m}m ${elapsed_s}s"
fi

case "$exit_reason" in
  loop_timeout)
    echo ""
    echo "** Loop terminated: total wall-clock timeout exceeded **"
    ;;
  round_timeout)
    echo ""
    echo "** Loop terminated: round wall-clock timeout exceeded **"
    ;;
esac
echo ""
echo "Cumulative totals:"
echo "  Issues raised: $cumulative_issues"
echo "  Applied:       $cumulative_applied"
echo "  Partial:       $cumulative_partial"
echo "  Skipped:       $cumulative_skipped"
echo ""
echo "Files created:"
if [ -f "$state_dir/critique_files" ]; then
  while IFS= read -r f; do
    [ -n "$f" ] && echo "  specification/critiques/$f"
  done < "$state_dir/critique_files"
fi
if [ -f "$state_dir/ack_files" ]; then
  while IFS= read -r f; do
    [ -n "$f" ] && echo "  specification/critiques/$f"
  done < "$state_dir/ack_files"
fi
echo "============================================"
