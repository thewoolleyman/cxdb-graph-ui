#!/usr/bin/env bash
set -euo pipefail

# Execute a SINGLE round of the critique-revise loop.
#
# This script is designed to be called once per round by the SKILL.md agent,
# so that each round's output is visible as soon as it completes (the Claude
# Code Bash tool buffers output until the command finishes).
#
# Multi-critic support: reads critic commands from config/critic-commands.conf
# and runs all critics in parallel. The loop only converges when ALL critics
# agree there are no major issues.
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
#   prev_issues       — sorted issue titles from previous round (union of all critics)
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
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CRITIC_CONFIG="$SKILL_DIR/config/critic-commands.conf"

CHECK_EXIT="$SCRIPT_DIR/check_exit.sh"
ROUND_SUMMARY="$SCRIPT_DIR/round_summary.sh"
ELAPSED_TIME="$SCRIPT_DIR/elapsed_time.sh"

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

# Elapsed time: use loop_start from state dir if available, otherwise use script start
if [ -f "$state_dir/loop_start" ]; then
  _loop_start=$(cat "$state_dir/loop_start")
else
  _loop_start=$(date +%s)
fi
_elapsed() { bash "$ELAPSED_TIME" "$_loop_start"; }
_step_header() { echo "*$1 (round $round of $max_rounds, elapsed $(_elapsed)): $2*"; }

# --- Round header ---

echo ""
echo "=========================================="
_step_header "Step A" "Start round"
echo "=========================================="

_status "round=$round step=A"

# --- Step B: Run critics (in parallel) ---

_status "round=$round step=B critique"
echo ""
_step_header "Step B" "Running critics"
echo "---"

# Snapshot critiques directory before running
mkdir -p "$CRITIQUES_DIR"
before_critique=$(ls "$CRITIQUES_DIR" 2>/dev/null | sort)

# Build the full critique prompt
full_critique_prompt="/spec:critique"
if [ -n "$critique_prompt" ]; then
  full_critique_prompt="/spec:critique $critique_prompt"
fi

# Read critic commands from config
if [ ! -f "$CRITIC_CONFIG" ]; then
  echo "ERROR: critic config not found: $CRITIC_CONFIG"
  exit 10
fi

# Parse config: strip comments and blank lines
critic_commands=()
while IFS= read -r line; do
  # Skip comments and blank lines
  [[ "$line" =~ ^[[:space:]]*# ]] && continue
  [[ -z "${line// /}" ]] && continue
  critic_commands+=("$line")
done < "$CRITIC_CONFIG"

if [ ${#critic_commands[@]} -eq 0 ]; then
  echo "ERROR: no critic commands found in $CRITIC_CONFIG"
  exit 10
fi

echo "Running ${#critic_commands[@]} critic(s) in parallel..."

# Launch all critics in parallel.
# Each critic's stdout/stderr is captured to a file so output isn't lost
# when the Bash tool's pipe closes (background processes inherit fd handles
# that the Bash tool doesn't drain properly).
critic_pids=()
critic_output_dir="$state_dir/critic_output"
mkdir -p "$critic_output_dir"
set +e
for i in "${!critic_commands[@]}"; do
  cmd="${critic_commands[$i]}"
  # Substitute variables
  cmd="${cmd//\{CRITIQUE_PROMPT\}/$full_critique_prompt}"
  cmd="${cmd//\{CRITIQUE_TOOLS\}/$CRITIQUE_TOOLS}"

  exit_file="$critic_output_dir/exit_$i"
  output_file="$critic_output_dir/output_$i"
  echo ""
  echo "  [Critic $((i+1))/${#critic_commands[@]}] Launching: ${cmd:0:80}..."

  # Run in background subshell, capture output and exit code to files
  (
    cd "$PROJ_DIR" && eval "$cmd" > "$output_file" 2>&1
    echo $? > "$exit_file"
  ) &
  critic_pids+=($!)
done

# Wait for all critics to finish
critic_failed=0
for i in "${!critic_pids[@]}"; do
  pid="${critic_pids[$i]}"
  wait "$pid" 2>/dev/null || true

  exit_file="$critic_output_dir/exit_$i"
  output_file="$critic_output_dir/output_$i"

  # Print this critic's captured output
  echo ""
  echo "  --- Critic $((i+1))/${#critic_commands[@]} output ---"
  if [ -f "$output_file" ]; then
    cat "$output_file"
  fi

  if [ -f "$exit_file" ]; then
    exit_code=$(cat "$exit_file")
  else
    exit_code=1
  fi
  if [ "$exit_code" -ne 0 ]; then
    echo ""
    echo "  WARNING: Critic $((i+1)) exited with code $exit_code"
    critic_failed=$((critic_failed + 1))
  fi
  echo "  --- End critic $((i+1)) ---"
done
rm -rf "$critic_output_dir"
set -e

if [ "$critic_failed" -eq "${#critic_commands[@]}" ]; then
  echo ""
  echo "ERROR: ALL critics failed"
  echo "Aborting round."
  exit 10
elif [ "$critic_failed" -gt 0 ]; then
  echo ""
  echo "  WARNING: $critic_failed of ${#critic_commands[@]} critic(s) failed, continuing with successful ones"
fi

echo ""
echo "---"

# --- Step C: Find new critique files ---

echo ""
_step_header "Step C" "Finding critique files"

after_critique=$(ls "$CRITIQUES_DIR" 2>/dev/null | sort)
critique_files=()

while IFS= read -r f; do
  if [ -n "$f" ] && [[ "$f" != *acknowledgement* ]]; then
    critique_files+=("$CRITIQUES_DIR/$f")
    echo "$f" >> "$state_dir/critique_files"
  fi
done < <(comm -13 <(echo "$before_critique") <(echo "$after_critique"))

if [ ${#critique_files[@]} -eq 0 ]; then
  echo "ERROR: no new critique files found after running critics"
  echo "Files before: $(echo "$before_critique" | tr '\n' ' ')"
  echo "Files after:  $(echo "$after_critique" | tr '\n' ' ')"
  exit 10
fi

echo "New critique files (${#critique_files[@]}):"
for f in "${critique_files[@]}"; do
  echo "  $f"
done

# --- Step D: Check exit condition (all critics must converge) ---

echo ""
_step_header "Step D" "Checking exit condition"

# We need a temp file for aggregating issue titles across all critics.
# check_exit.sh writes to prev_issues_file as a side effect, so we use
# a per-critic temp file and merge after.
all_issues_tmp=$(mktemp)
trap 'rm -f "$CRASH_LOG" "$all_issues_tmp" 2>/dev/null' EXIT

any_continue=0
any_stuck=0
all_converged=1

for crit_file in "${critique_files[@]}"; do
  echo ""
  echo "  Checking: $(basename "$crit_file")"

  # Use a per-critic prev_issues to avoid cross-contamination
  per_critic_prev=$(mktemp)
  cp "$prev_issues_file" "$per_critic_prev"

  set +e
  check_result=$("$CHECK_EXIT" "$crit_file" "$exit_criteria" "$per_critic_prev")
  check_exit_code=$?
  set -e

  echo "  $check_result"

  if [ "$check_exit_code" -eq 0 ]; then
    any_continue=1
    all_converged=0
  elif [ "$check_exit_code" -eq 1 ]; then
    : # converged for this critic
  elif [ "$check_exit_code" -eq 2 ]; then
    any_stuck=1
    all_converged=0
  else
    echo "ERROR: check_exit.sh returned unexpected code $check_exit_code"
    rm -f "$per_critic_prev"
    exit 10
  fi

  # Aggregate issue titles for stuck detection in next round
  # per_critic_prev now contains the sorted issues from this critic
  cat "$per_critic_prev" >> "$all_issues_tmp"
  rm -f "$per_critic_prev"
done

# Save merged issue titles for next round's stuck detection
sort -u "$all_issues_tmp" > "$prev_issues_file"
rm -f "$all_issues_tmp"

# Decision: all critics must converge
if [ "$all_converged" -eq 1 ]; then
  echo ""
  echo "ALL critics converged."
  echo "$cumulative_issues $cumulative_applied $cumulative_partial $cumulative_skipped" > "$state_dir/cumulative"
  exit 1
elif [ "$any_continue" -eq 1 ]; then
  echo ""
  echo "Major issues found — continuing to revise."
elif [ "$any_stuck" -eq 1 ]; then
  echo ""
  echo "Stuck — no new issues from any critic."
  echo "$cumulative_issues $cumulative_applied $cumulative_partial $cumulative_skipped" > "$state_dir/cumulative"
  exit 2
fi

# --- Step E: Run revise ---

_status "round=$round step=E revise"

# Extract unique version identifiers from critique files for the status header
_revise_versions=""
for _cf in "${critique_files[@]}"; do
  _v=$(basename "$_cf" | grep -oE '^v[0-9]+')
  [ -n "$_v" ] && _revise_versions="${_revise_versions:+$_revise_versions, }$_v"
done

echo ""
_step_header "Step E" "Running /spec:revise for ${_revise_versions:-unknown}"
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
_step_header "Step F" "Round summary"

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
