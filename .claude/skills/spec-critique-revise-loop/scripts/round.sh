#!/usr/bin/env bash
set -euo pipefail

# Execute a SINGLE round of the critique-revise loop.
#
# This script is designed to be called once per round by the SKILL.md agent,
# so that each round's output is visible as soon as it completes (the Claude
# Code Bash tool buffers output until the command finishes).
#
# Usage: round.sh [options]
#   --round <N>              Current round number (required)
#   --max-rounds <N>         Maximum rounds allowed
#   --exit-criteria <str>    no_issues_found | no_major_issues_found
#   --state-dir <dir>        Directory for persisting state between rounds
#   --critique-prompt <str>  Extra prompt text for critique
#   --revise-prompt <str>    Extra prompt text for revise
#
# Exit codes:
#   0 = continue (more rounds needed)
#   1 = converged (exit condition met)
#   2 = stuck (same issues as previous round)
#   10 = error (critique or revise failed)
#
# State directory contents (read/written between rounds):
#   prev_issues       — sorted issue titles from previous round
#   cumulative        — "issues applied partial skipped" counts
#   critique_files    — newline-separated list of critique files created
#   ack_files         — newline-separated list of acknowledgement files created

# --- Parse arguments ---

round=""
max_rounds=3
exit_criteria="no_major_issues_found"
state_dir=""
critique_prompt=""
revise_prompt=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --round)           round="$2"; shift 2 ;;
    --max-rounds)      max_rounds="$2"; shift 2 ;;
    --exit-criteria)   exit_criteria="$2"; shift 2 ;;
    --state-dir)       state_dir="$2"; shift 2 ;;
    --critique-prompt) critique_prompt="$2"; shift 2 ;;
    --revise-prompt)   revise_prompt="$2"; shift 2 ;;
    *) echo "WARNING: unknown argument: $1"; shift ;;
  esac
done

if [ -z "$round" ] || [ -z "$state_dir" ]; then
  echo "ERROR: --round and --state-dir are required"
  exit 10
fi

# --- Resolve paths ---

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# scripts/ → spec-critique-revise-loop/ → skills/ → .claude/ → project root
PROJ_DIR="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
CRITIQUES_DIR="$PROJ_DIR/specification/critiques"

CHECK_EXIT="$SCRIPT_DIR/check_exit.sh"
ROUND_SUMMARY="$SCRIPT_DIR/round_summary.sh"

# --- Allowed tools for each sub-skill ---

CRITIQUE_TOOLS="Read,Write,Glob,Bash(ls:*),Bash(pwd:*),Bash(date:*)"
REVISE_TOOLS="Read,Write,Edit,Glob,Bash(ls:*),Bash(pwd:*),Bash(date:*)"

# Allow nested claude invocation
unset CLAUDECODE 2>/dev/null || true

# --- Initialize state dir ---

mkdir -p "$state_dir"
prev_issues_file="$state_dir/prev_issues"
touch "$prev_issues_file"

# Read cumulative counts
if [ -f "$state_dir/cumulative" ]; then
  read -r cumulative_issues cumulative_applied cumulative_partial cumulative_skipped < "$state_dir/cumulative"
else
  cumulative_issues=0
  cumulative_applied=0
  cumulative_partial=0
  cumulative_skipped=0
fi

# --- Crash detection ---

CRASH_LOG="/tmp/critique-revise-round.$$.status"
trap 'rm -f "$CRASH_LOG" 2>/dev/null' EXIT
_status() { echo "$*" > "$CRASH_LOG"; }

# --- Round header ---

echo ""
echo "=========================================="
echo "[STEP A] round = $round of $max_rounds"
echo "=========================================="

_status "round=$round step=A"

# --- Step B: Run critique ---

_status "round=$round step=B critique"
echo ""
echo "[STEP B] (round $round of $max_rounds) Running /spec:critique..."
echo "---"

# Snapshot critiques directory before running
mkdir -p "$CRITIQUES_DIR"
before_critique=$(ls "$CRITIQUES_DIR" 2>/dev/null | sort)

# Build the critique prompt
full_critique_prompt="/spec:critique"
if [ -n "$critique_prompt" ]; then
  full_critique_prompt="/spec:critique $critique_prompt"
fi

# Run critique as a non-interactive claude session
set +e
(cd "$PROJ_DIR" && claude -p "$full_critique_prompt" --allowed-tools "$CRITIQUE_TOOLS")
critique_exit=$?
set -e

if [ "$critique_exit" -ne 0 ]; then
  echo ""
  echo "ERROR: /spec:critique failed with exit code $critique_exit"
  echo "Aborting round."
  exit 10
fi

echo ""
echo "---"

# --- Step C: Find the new critique file ---

echo ""
echo "[STEP C] (round $round of $max_rounds) Finding critique file..."

after_critique=$(ls "$CRITIQUES_DIR" 2>/dev/null | sort)
critique_file=""

while IFS= read -r f; do
  if [ -n "$f" ] && [[ "$f" != *acknowledgement* ]]; then
    critique_file="$CRITIQUES_DIR/$f"
    echo "$f" >> "$state_dir/critique_files"
  fi
done < <(comm -13 <(echo "$before_critique") <(echo "$after_critique"))

if [ -z "$critique_file" ]; then
  echo "ERROR: no new critique file found after running /spec:critique"
  echo "Files before: $(echo "$before_critique" | tr '\n' ' ')"
  echo "Files after:  $(echo "$after_critique" | tr '\n' ' ')"
  exit 10
fi

echo "New critique file: $critique_file"

# --- Step D: Check exit condition ---

echo ""
echo "[STEP D] (round $round of $max_rounds) Checking exit condition..."

set +e
check_result=$("$CHECK_EXIT" "$critique_file" "$exit_criteria" "$prev_issues_file")
check_exit_code=$?
set -e

echo "$check_result"

if [ "$check_exit_code" -eq 1 ]; then
  # Converged — save state and exit
  echo "$cumulative_issues $cumulative_applied $cumulative_partial $cumulative_skipped" > "$state_dir/cumulative"
  exit 1
elif [ "$check_exit_code" -eq 2 ]; then
  # Stuck — save state and exit
  echo "$cumulative_issues $cumulative_applied $cumulative_partial $cumulative_skipped" > "$state_dir/cumulative"
  exit 2
elif [ "$check_exit_code" -ne 0 ]; then
  echo "ERROR: check_exit.sh returned unexpected code $check_exit_code"
  exit 10
fi

# --- Step E: Run revise ---

_status "round=$round step=E revise"
echo ""
echo "[STEP E] (round $round of $max_rounds) Running /spec:revise..."
echo "---"

# Snapshot before revise
before_revise=$(ls "$CRITIQUES_DIR" 2>/dev/null | sort)

# Build the revise prompt
full_revise_prompt="/spec:revise"
if [ -n "$revise_prompt" ]; then
  full_revise_prompt="/spec:revise $revise_prompt"
fi

# Run revise as a non-interactive claude session
set +e
(cd "$PROJ_DIR" && claude -p "$full_revise_prompt" --allowed-tools "$REVISE_TOOLS")
revise_exit=$?
set -e

if [ "$revise_exit" -ne 0 ]; then
  echo ""
  echo "ERROR: /spec:revise failed with exit code $revise_exit"
  echo "Aborting round."
  exit 10
fi

echo ""
echo "---"

# --- Step F: Round summary ---

echo ""
echo "[STEP F] (round $round of $max_rounds) Round summary"

after_revise=$(ls "$CRITIQUES_DIR" 2>/dev/null | sort)
round_ack_files=()

while IFS= read -r f; do
  if [ -n "$f" ] && [[ "$f" == *acknowledgement* ]]; then
    round_ack_files+=("$CRITIQUES_DIR/$f")
    echo "$f" >> "$state_dir/ack_files"
  fi
done < <(comm -13 <(echo "$before_revise") <(echo "$after_revise"))

if [ ${#round_ack_files[@]} -eq 0 ]; then
  echo "  WARNING: no new acknowledgement files found"
else
  # Print per-issue summary
  "$ROUND_SUMMARY" "${round_ack_files[@]}"

  # Extract counts for cumulative tracking
  counts_line=$("$ROUND_SUMMARY" "${round_ack_files[@]}" | tail -1)
  round_issues=$(echo "$counts_line" | sed -n 's/.*Issues: \([0-9]*\).*/\1/p')
  round_applied=$(echo "$counts_line" | sed -n 's/.*Applied: \([0-9]*\).*/\1/p')
  round_partial=$(echo "$counts_line" | sed -n 's/.*Partial: \([0-9]*\).*/\1/p')
  round_skipped=$(echo "$counts_line" | sed -n 's/.*Skipped: \([0-9]*\).*/\1/p')
  round_issues=${round_issues:-0}
  round_applied=${round_applied:-0}
  round_partial=${round_partial:-0}
  round_skipped=${round_skipped:-0}

  cumulative_issues=$((cumulative_issues + round_issues))
  cumulative_applied=$((cumulative_applied + round_applied))
  cumulative_partial=$((cumulative_partial + round_partial))
  cumulative_skipped=$((cumulative_skipped + round_skipped))
fi

# Save cumulative state
echo "$cumulative_issues $cumulative_applied $cumulative_partial $cumulative_skipped" > "$state_dir/cumulative"

echo ""
echo "=== ROUND $round of $max_rounds COMPLETE ==="

# Exit 0 = continue to next round
exit 0
