#!/usr/bin/env bash
set -euo pipefail

# Tests for report.sh timeout-related output:
#   1. loop_timeout exit reason prints timeout message
#   2. round_timeout exit reason prints timeout message
#   3. Elapsed time is printed when loop_start file exists
#   4. No elapsed time when loop_start file is missing
#   5. Non-timeout exit reasons don't print timeout messages

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts" && pwd)"
REPORT="$SCRIPT_DIR/report.sh"

TMPDIR_TEST=$(mktemp -d)
trap 'rm -rf "$TMPDIR_TEST"' EXIT

pass=0
fail=0

assert_exit() {
  local test_name="$1" expected="$2" actual="$3" output="$4"
  if [ "$expected" -eq "$actual" ]; then
    echo "  PASS: $test_name (exit=$actual)"
    pass=$((pass + 1))
  else
    echo "  FAIL: $test_name (expected exit=$expected, got exit=$actual)"
    echo "        output: $output"
    fail=$((fail + 1))
  fi
}

assert_contains() {
  local test_name="$1" expected="$2" actual="$3"
  if echo "$actual" | grep -qF "$expected"; then
    echo "  PASS: $test_name"
    pass=$((pass + 1))
  else
    echo "  FAIL: $test_name (expected to contain '$expected')"
    echo "        actual: $actual"
    fail=$((fail + 1))
  fi
}

assert_not_contains() {
  local test_name="$1" unexpected="$2" actual="$3"
  if echo "$actual" | grep -qF "$unexpected"; then
    echo "  FAIL: $test_name (should NOT contain '$unexpected')"
    echo "        actual: $actual"
    fail=$((fail + 1))
  else
    echo "  PASS: $test_name"
    pass=$((pass + 1))
  fi
}

make_state_dir() {
  local sd="$TMPDIR_TEST/state_${RANDOM}"
  mkdir -p "$sd"
  echo "0 0 0 0" > "$sd/cumulative"
  echo "$sd"
}

echo "=== test_report_timeout.sh ==="

# --- Test 1: loop_timeout exit reason ---
echo ""
echo "Test 1: loop_timeout exit reason prints timeout message"

sd=$(make_state_dir)
# Set loop_start to 90 minutes ago
echo $(( $(date +%s) - 5400 )) > "$sd/loop_start"

set +e
output=$(bash "$REPORT" --state-dir "$sd" --rounds-completed 2 --exit-reason "loop_timeout" --exit-criteria "no_major_issues_found" 2>&1)
rc=$?
set -e

assert_exit "loop_timeout exits 0" 0 "$rc" "$output"
assert_contains "shows loop_timeout reason" "Exit reason:       loop_timeout" "$output"
assert_contains "prints loop timeout message" "total wall-clock timeout exceeded" "$output"
assert_contains "prints elapsed time" "Elapsed time:" "$output"

# --- Test 2: round_timeout exit reason ---
echo ""
echo "Test 2: round_timeout exit reason prints timeout message"

sd=$(make_state_dir)
echo $(( $(date +%s) - 3000 )) > "$sd/loop_start"

set +e
output=$(bash "$REPORT" --state-dir "$sd" --rounds-completed 1 --exit-reason "round_timeout" --exit-criteria "no_major_issues_found" 2>&1)
rc=$?
set -e

assert_exit "round_timeout exits 0" 0 "$rc" "$output"
assert_contains "shows round_timeout reason" "Exit reason:       round_timeout" "$output"
assert_contains "prints round timeout message" "round wall-clock timeout exceeded" "$output"

# --- Test 3: Elapsed time with loop_start ---
echo ""
echo "Test 3: Elapsed time is printed when loop_start exists"

sd=$(make_state_dir)
# Started 125 seconds ago → should show "2m 5s"
echo $(( $(date +%s) - 125 )) > "$sd/loop_start"

set +e
output=$(bash "$REPORT" --state-dir "$sd" --rounds-completed 1 --exit-reason "converged" --exit-criteria "no_major_issues_found" 2>&1)
rc=$?
set -e

assert_exit "converged with elapsed exits 0" 0 "$rc" "$output"
assert_contains "has elapsed time line" "Elapsed time:" "$output"
assert_contains "shows minutes" "2m" "$output"

# --- Test 4: No elapsed time without loop_start ---
echo ""
echo "Test 4: No elapsed time when loop_start is missing"

sd=$(make_state_dir)
# Don't create loop_start

set +e
output=$(bash "$REPORT" --state-dir "$sd" --rounds-completed 1 --exit-reason "converged" --exit-criteria "no_major_issues_found" 2>&1)
rc=$?
set -e

assert_exit "no loop_start exits 0" 0 "$rc" "$output"
assert_not_contains "no elapsed time" "Elapsed time:" "$output"

# --- Test 5: Non-timeout exit reasons don't print timeout messages ---
echo ""
echo "Test 5: Non-timeout exit reasons don't print timeout messages"

for reason in converged stuck round_limit; do
  sd=$(make_state_dir)
  echo "$(date +%s)" > "$sd/loop_start"

  set +e
  output=$(bash "$REPORT" --state-dir "$sd" --rounds-completed 1 --exit-reason "$reason" --exit-criteria "no_major_issues_found" 2>&1)
  rc=$?
  set -e

  assert_exit "$reason exits 0" 0 "$rc" "$output"
  assert_not_contains "$reason: no timeout exceeded msg" "timeout exceeded" "$output"
done

# --- Test 6: Report still shows standard fields with timeout ---
echo ""
echo "Test 6: Timeout report includes all standard fields"

sd=$(make_state_dir)
echo "5 3 1 1" > "$sd/cumulative"
echo "v10-opus.md" > "$sd/critique_files"
echo "v10-opus-acknowledgement.md" > "$sd/ack_files"
echo $(( $(date +%s) - 7200 )) > "$sd/loop_start"

set +e
output=$(bash "$REPORT" --state-dir "$sd" --rounds-completed 2 --exit-reason "loop_timeout" --exit-criteria "no_issues_found" 2>&1)
rc=$?
set -e

assert_exit "full timeout report exits 0" 0 "$rc" "$output"
assert_contains "has FINAL REPORT header" "FINAL REPORT" "$output"
assert_contains "has rounds completed" "Rounds completed:  2" "$output"
assert_contains "has exit criteria" "Exit criteria:     no_issues_found" "$output"
assert_contains "has cumulative issues" "Issues raised: 5" "$output"
assert_contains "has applied count" "Applied:       3" "$output"
assert_contains "has critique file" "v10-opus.md" "$output"
assert_contains "has ack file" "v10-opus-acknowledgement.md" "$output"
assert_contains "has timeout message" "total wall-clock timeout exceeded" "$output"

echo ""
echo "=== report_timeout: $pass passed, $fail failed ==="
[ "$fail" -eq 0 ] || exit 1
