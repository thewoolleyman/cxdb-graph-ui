#!/usr/bin/env bash
set -euo pipefail

# Deterministic critique-revise loop driver.
#
# This script owns the loop. The LLM (via claude -p) owns critique and revise.
# Exit conditions are checked with grep/awk — no LLM involvement in loop control.
#
# Multi-critic support: reads critic commands from config/critic-commands.conf
# and runs all critics in parallel. The loop only converges when ALL critics
# agree there are no major issues.
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
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CRITIC_CONFIG="$SKILL_DIR/config/critic-commands.conf"

CHECK_EXIT="$SCRIPT_DIR/check_exit.sh"
ROUND_SUMMARY="$SCRIPT_DIR/round_summary.sh"

# --- Allowed tools for each sub-skill (matches SKILL.md allowed-tools) ---

# Comma-separated to avoid shell glob expansion on Bash(ls:*)
CRITIQUE_TOOLS="Read,Write,Glob,Bash(ls:*),Bash(pwd:*),Bash(date:*)"
REVISE_TOOLS="Read,Write,Edit,Glob,Bash(ls:*),Bash(pwd:*),Bash(date:*)"

# Allow nested claude invocation (we're called from inside a claude session)
unset CLAUDECODE 2>/dev/null || true

# --- Crash detection ---
# Write a status file to /tmp so a crash can be diagnosed.
# This is ONLY for crash detection — all real output goes to stdout/stderr.

CRASH_LOG="/tmp/critique-revise-loop.$$.status"
trap 'rm -f "$prev_issues_file" "$CRASH_LOG" 2>/dev/null' EXIT
_status() { echo "$*" > "$CRASH_LOG"; }
_elapsed() { bash "$ELAPSED_TIME" "$loop_start"; }
_step_header() { echo "*$1 (round $round of $max_rounds, elapsed $(_elapsed)): $2*"; }

# --- Read critic config ---

if [ ! -f "$CRITIC_CONFIG" ]; then
  echo "ERROR: critic config not found: $CRITIC_CONFIG"
  exit 1
fi

critic_commands=()
while IFS= read -r line; do
  [[ "$line" =~ ^[[:space:]]*# ]] && continue
  [[ -z "${line// /}" ]] && continue
  critic_commands+=("$line")
done < "$CRITIC_CONFIG"

if [ ${#critic_commands[@]} -eq 0 ]; then
  echo "ERROR: no critic commands found in $CRITIC_CONFIG"
  exit 1
fi

# --- State ---

round=0
prev_issues_file=$(mktemp)
loop_start=$(date +%s)

ELAPSED_TIME="$SCRIPT_DIR/elapsed_time.sh"

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
echo "Critics:         ${#critic_commands[@]}"
echo "Critique prompt: ${critique_prompt:-(none)}"
echo "Revise prompt:   ${revise_prompt:-(none)}"
echo "Project dir:     $PROJ_DIR"
echo "============================================"
echo ""

# --- Step 4: Process unacknowledged critiques ---

echo ""
echo "============================================"
echo "  Step 4: Process unacknowledged critiques"
echo "============================================"

mkdir -p "$CRITIQUES_DIR"
unacked=()
for _f in "$CRITIQUES_DIR"/v*-*.md; do
  [ -f "$_f" ] || continue
  [[ "$_f" == *acknowledgement* ]] && continue
  _base=$(basename "$_f" .md)
  if [ ! -f "$CRITIQUES_DIR/${_base}-acknowledgement.md" ]; then
    unacked+=("$(basename "$_f")")
  fi
done

if [ ${#unacked[@]} -gt 0 ]; then
  echo "Found ${#unacked[@]} unacknowledged critique(s):"
  for _name in "${unacked[@]}"; do
    echo "  $_name"
  done
  echo ""
  echo "Running /spec:revise to process them before starting the loop..."

  full_revise_prompt_preloop="/spec:revise"
  if [ -n "$revise_prompt" ]; then
    full_revise_prompt_preloop="/spec:revise $revise_prompt"
  fi

  set +e
  (cd "$PROJ_DIR" && claude -p "$full_revise_prompt_preloop" --allowed-tools "$REVISE_TOOLS")
  preloop_revise_exit=$?
  set -e

  if [ "$preloop_revise_exit" -ne 0 ]; then
    echo "ERROR: pre-loop /spec:revise failed with exit code $preloop_revise_exit"
    echo "Aborting loop."
    exit 1
  fi
  echo "Pre-loop revise complete."
else
  echo "No unacknowledged critiques. Proceeding to loop."
fi

# --- Main loop ---

while true; do
  round=$((round + 1))

  echo ""
  echo "=========================================="
  _step_header "Step A" "Start round"
  echo "=========================================="

  _status "round=$round step=A"

  # Check round limit BEFORE doing work
  if [ "$round" -gt "$max_rounds" ]; then
    round=$((round - 1))  # don't count the round that didn't execute
    exit_reason="round_limit"
    break
  fi

  # --- Step B: Run critics (in parallel) ---

  _status "round=$round step=B critique"
  echo ""
  _step_header "Step B" "Running ${#critic_commands[@]} critic(s)"
  echo "---"

  # Snapshot critiques directory before running
  mkdir -p "$CRITIQUES_DIR"
  before_critique=$(ls "$CRITIQUES_DIR" 2>/dev/null | sort)

  # Build critique prompt expansions (type-aware):
  # - skill/raw critics: {CRITIQUE_PROMPT} → "/spec:critique [extra]"
  # - bash critics:      {CRITIQUE_PROMPT} → ". Additional instructions: [extra]" (or "")
  skill_critique_prompt="/spec:critique"
  bash_critique_prompt=""
  if [ -n "$critique_prompt" ]; then
    skill_critique_prompt="/spec:critique $critique_prompt"
    bash_critique_prompt=". Additional instructions: $critique_prompt"
  fi

  # Launch all critics in parallel.
  # Each critic's output is captured to a file and printed after wait.
  critic_pids=()
  critic_output_dir=$(mktemp -d)
  set +e
  for i in "${!critic_commands[@]}"; do
    cmd="${critic_commands[$i]}"
    # Substitute {CRITIQUE_PROMPT} based on critic type
    if [[ "$cmd" =~ ^bash[[:space:]] ]]; then
      cmd="${cmd//\{CRITIQUE_PROMPT\}/$bash_critique_prompt}"
    else
      cmd="${cmd//\{CRITIQUE_PROMPT\}/$skill_critique_prompt}"
    fi
    cmd="${cmd//\{CRITIQUE_TOOLS\}/$CRITIQUE_TOOLS}"

    exit_file="$critic_output_dir/exit_$i"
    output_file="$critic_output_dir/output_$i"
    echo ""
    echo "  [Critic $((i+1))/${#critic_commands[@]}] Launching: ${cmd:0:80}..."

    (
      cd "$PROJ_DIR" && eval "$cmd" > "$output_file" 2>&1
      echo $? > "$exit_file"
    ) &
    critic_pids+=($!)
  done

  # Wait for all critics
  critic_failed=0
  for i in "${!critic_pids[@]}"; do
    pid="${critic_pids[$i]}"
    wait "$pid" 2>/dev/null || true

    exit_file="$critic_output_dir/exit_$i"
    output_file="$critic_output_dir/output_$i"

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
    echo "Aborting loop."
    exit 1
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
  round_critique_files=()

  while IFS= read -r f; do
    if [ -n "$f" ] && [[ "$f" != *acknowledgement* ]]; then
      round_critique_files+=("$CRITIQUES_DIR/$f")
      critique_files_created+=("$f")
    fi
  done < <(comm -13 <(echo "$before_critique") <(echo "$after_critique"))

  if [ ${#round_critique_files[@]} -eq 0 ]; then
    echo "ERROR: no new critique files found after running critics"
    echo "Files before: $(echo "$before_critique" | tr '\n' ' ')"
    echo "Files after:  $(echo "$after_critique" | tr '\n' ' ')"
    exit 1
  fi

  echo "New critique files (${#round_critique_files[@]}):"
  for f in "${round_critique_files[@]}"; do
    echo "  $f"
  done

  # --- Step D: Check exit condition (all critics must converge) ---

  echo ""
  _step_header "Step D" "Checking exit condition"

  all_issues_tmp=$(mktemp)
  any_continue=0
  any_stuck=0
  all_converged=1

  for crit_file in "${round_critique_files[@]}"; do
    echo ""
    echo "  Checking: $(basename "$crit_file")"

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
      rm -f "$per_critic_prev" "$all_issues_tmp"
      exit 1
    fi

    cat "$per_critic_prev" >> "$all_issues_tmp"
    rm -f "$per_critic_prev"
  done

  sort -u "$all_issues_tmp" > "$prev_issues_file"
  rm -f "$all_issues_tmp"

  # Record outcome but always continue to Step E (revise) so that
  # acknowledgement files are written for every critique, even on convergence.
  if [ "$all_converged" -eq 1 ]; then
    echo ""
    echo "ALL critics converged. Running revise to write acknowledgements."
    exit_reason="converged"
  elif [ "$any_continue" -eq 1 ]; then
    echo ""
    echo "Major issues found — continuing to revise."
  elif [ "$any_stuck" -eq 1 ]; then
    echo ""
    echo "Stuck — no new issues from any critic. Running revise to write acknowledgements."
    exit_reason="stuck"
  fi

  # --- Step E: Run revise (always — writes acknowledgements for new critiques) ---

  _status "round=$round step=E revise"

  # Extract unique version identifiers from critique files for the status header
  _revise_versions=""
  for _cf in "${round_critique_files[@]}"; do
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
    echo "Aborting loop."
    exit 1
  fi

  echo ""
  echo "---"

  # --- Step F: Round summary ---

  echo ""
  _step_header "Step F" "Round summary"

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

  # Break after acknowledgements have been written (converged or stuck)
  if [ -n "$exit_reason" ]; then
    break
  fi

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
