#!/usr/bin/env bash
set -euo pipefail

# Deterministic critique-revise loop driver.
#
# This script owns the loop. The LLM (via claude -p) owns critique and revise.
# Exit conditions are checked with grep/awk — no LLM involvement in loop control.
#
# Usage: loop.sh [options]
#   --exit-criteria <no_issues_found|no_major_issues_found>
#   --max-rounds <N>
#   --critique-prompt <string>
#   --revise-prompt <string>

# --- Parse arguments ---

exit_criteria="no_major_issues_found"
max_rounds=3
critique_prompt=""
revise_prompt=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --exit-criteria)  exit_criteria="$2"; shift 2 ;;
    --max-rounds)     max_rounds="$2"; shift 2 ;;
    --critique-prompt) critique_prompt="$2"; shift 2 ;;
    --revise-prompt)  revise_prompt="$2"; shift 2 ;;
    *) echo "WARNING: unknown argument: $1"; shift ;;
  esac
done

# --- Resolve paths ---

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# scripts/ → spec-critique-revise-loop/ → skills/ → .claude/ → project root
PROJ_DIR="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
CRITIQUES_DIR="$PROJ_DIR/specification/critiques"

CHECK_EXIT="$SCRIPT_DIR/check_exit.sh"
ROUND_SUMMARY="$SCRIPT_DIR/round_summary.sh"

# --- Allowed tools for each sub-skill (matches SKILL.md allowed-tools) ---

# Comma-separated to avoid shell glob expansion on Bash(ls:*)
CRITIQUE_TOOLS="Read,Write,Glob,Bash(ls:*),Bash(pwd:*),Bash(date:*)"
REVISE_TOOLS="Read,Write,Edit,Glob,Bash(ls:*),Bash(pwd:*),Bash(date:*)"

# Allow nested claude invocation (we're called from inside a claude session)
unset CLAUDECODE 2>/dev/null || true

# --- State ---

round=0
prev_issues_file=$(mktemp)
trap 'rm -f "$prev_issues_file"' EXIT

cumulative_issues=0
cumulative_applied=0
cumulative_partial=0
cumulative_skipped=0
exit_reason=""
critique_files_created=()
ack_files_created=()

# --- Header ---

echo ""
echo "============================================"
echo "  CRITIQUE-REVISE LOOP (deterministic bash)"
echo "============================================"
echo "Exit criteria:   $exit_criteria"
echo "Max rounds:      $max_rounds"
echo "Critique prompt: ${critique_prompt:-(none)}"
echo "Revise prompt:   ${revise_prompt:-(none)}"
echo "Project dir:     $PROJ_DIR"
echo "============================================"
echo ""

# --- Main loop ---

while true; do
  round=$((round + 1))

  echo ""
  echo "=========================================="
  echo "[STEP A] round = $round of $max_rounds"
  echo "=========================================="

  # Check round limit BEFORE doing work
  if [ "$round" -gt "$max_rounds" ]; then
    round=$((round - 1))  # don't count the round that didn't execute
    exit_reason="round_limit"
    break
  fi

  # --- Step B: Run critique ---

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
    echo "Aborting loop."
    exit 1
  fi

  echo ""
  echo "---"

  # --- Step C: Find the new critique file ---

  echo ""
  echo "[STEP C] (round $round of $max_rounds) Finding critique file..."

  after_critique=$(ls "$CRITIQUES_DIR" 2>/dev/null | sort)
  critique_file=""

  # Find files that appeared after the critique run, excluding acknowledgements
  while IFS= read -r f; do
    if [ -n "$f" ] && [[ "$f" != *acknowledgement* ]]; then
      critique_file="$CRITIQUES_DIR/$f"
      critique_files_created+=("$f")
    fi
  done < <(comm -13 <(echo "$before_critique") <(echo "$after_critique"))

  if [ -z "$critique_file" ]; then
    echo "ERROR: no new critique file found after running /spec:critique"
    echo "Files before: $(echo "$before_critique" | tr '\n' ' ')"
    echo "Files after:  $(echo "$after_critique" | tr '\n' ' ')"
    exit 1
  fi

  echo "New critique file: $critique_file"

  # --- Step D: Check exit condition ---

  echo ""
  echo "[STEP D] (round $round of $max_rounds) Checking exit condition..."

  # check_exit.sh uses exit codes: 0=continue, 1=converged, 2=stuck
  set +e
  check_result=$("$CHECK_EXIT" "$critique_file" "$exit_criteria" "$prev_issues_file")
  check_exit_code=$?
  set -e

  echo "$check_result"

  if [ "$check_exit_code" -eq 1 ]; then
    exit_reason="converged"
    break
  elif [ "$check_exit_code" -eq 2 ]; then
    exit_reason="stuck"
    break
  elif [ "$check_exit_code" -ne 0 ]; then
    echo "ERROR: check_exit.sh returned unexpected code $check_exit_code"
    exit 1
  fi

  # --- Step E: Run revise ---

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
    echo "Aborting loop."
    exit 1
  fi

  echo ""
  echo "---"

  # --- Step F: Round summary ---

  echo ""
  echo "[STEP F] (round $round of $max_rounds) Round summary"

  after_revise=$(ls "$CRITIQUES_DIR" 2>/dev/null | sort)
  round_ack_files=()

  # Find new acknowledgement files
  while IFS= read -r f; do
    if [ -n "$f" ] && [[ "$f" == *acknowledgement* ]]; then
      round_ack_files+=("$CRITIQUES_DIR/$f")
      ack_files_created+=("$f")
    fi
  done < <(comm -13 <(echo "$before_revise") <(echo "$after_revise"))

  if [ ${#round_ack_files[@]} -eq 0 ]; then
    echo "  WARNING: no new acknowledgement files found"
  else
    # Print per-issue summary
    "$ROUND_SUMMARY" "${round_ack_files[@]}"

    # Extract counts for cumulative tracking (macOS-compatible, no grep -P)
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

  echo ""
  echo "=== ROUND $round of $max_rounds COMPLETE ==="

done

# --- Final report ---

echo ""
echo "============================================"
echo "  FINAL REPORT"
echo "============================================"
echo "Rounds completed:  $round"
echo "Exit reason:       $exit_reason"
echo "Exit criteria:     $exit_criteria"
echo ""
echo "Cumulative totals:"
echo "  Issues raised: $cumulative_issues"
echo "  Applied:       $cumulative_applied"
echo "  Partial:       $cumulative_partial"
echo "  Skipped:       $cumulative_skipped"
echo ""
echo "Files created:"
for f in "${critique_files_created[@]+"${critique_files_created[@]}"}"; do
  echo "  specification/critiques/$f"
done
for f in "${ack_files_created[@]+"${ack_files_created[@]}"}"; do
  echo "  specification/critiques/$f"
done
echo "============================================"
