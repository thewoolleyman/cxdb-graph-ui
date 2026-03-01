#!/usr/bin/env bash
set -euo pipefail

# Unit tests for elapsed_time.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts" && pwd)"
ELAPSED_TIME="$SCRIPT_DIR/elapsed_time.sh"

pass=0
fail=0

assert_eq() {
  local test_name="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    echo "  PASS: $test_name"
    pass=$((pass + 1))
  else
    echo "  FAIL: $test_name (expected '$expected', got '$actual')"
    fail=$((fail + 1))
  fi
}

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

assert_matches() {
  local test_name="$1" pattern="$2" actual="$3"
  if echo "$actual" | grep -qE "$pattern"; then
    echo "  PASS: $test_name"
    pass=$((pass + 1))
  else
    echo "  FAIL: $test_name (expected to match '$pattern', got '$actual')"
    fail=$((fail + 1))
  fi
}

echo "=== test_elapsed_time.sh ==="

# Helper: compute start epoch for a given offset, then immediately invoke the
# script. This eliminates the race between capturing `now` and the script
# calling `date +%s` internally.
run_elapsed() {
  local offset="$1"
  local start=$(( $(date +%s) - offset ))
  bash "$ELAPSED_TIME" "$start" 2>&1
}

# Test 1: Just started (0 seconds elapsed)
echo ""
echo "--- Test: zero elapsed ---"
set +e
output=$(run_elapsed 0)
rc=$?
set -e
assert_exit "zero elapsed exits 0" 0 "$rc" "$output"
assert_eq "zero elapsed is 0:00" "0:00" "$output"

# Test 2: 90 seconds elapsed → 1:30
echo ""
echo "--- Test: 90 seconds ---"
output=$(run_elapsed 90)
assert_eq "90s is 1:30" "1:30" "$output"

# Test 3: Exactly 5 minutes → 5:00
echo ""
echo "--- Test: 5 minutes ---"
output=$(run_elapsed 300)
assert_eq "300s is 5:00" "5:00" "$output"

# Test 4: 7 seconds → 0:07 (zero-padded seconds)
echo ""
echo "--- Test: zero-padded seconds ---"
output=$(run_elapsed 7)
assert_eq "7s is 0:07" "0:07" "$output"

# Test 5: 2 hours 3 minutes 45 seconds → 123:45
echo ""
echo "--- Test: large elapsed ---"
output=$(run_elapsed 7425)
assert_eq "7425s is 123:45" "123:45" "$output"

# Test 6: 59 seconds → 0:59
echo ""
echo "--- Test: 59 seconds ---"
output=$(run_elapsed 59)
assert_eq "59s is 0:59" "0:59" "$output"

# Test 7: 60 seconds → 1:00
echo ""
echo "--- Test: 60 seconds ---"
output=$(run_elapsed 60)
assert_eq "60s is 1:00" "1:00" "$output"

# Test 8: Output format matches M:SS or MM:SS pattern
echo ""
echo "--- Test: output format ---"
output=$(run_elapsed 185)
assert_matches "format is N+:NN" '^[0-9]+:[0-9]{2}$' "$output"

# Test 9: Missing arguments
echo ""
echo "--- Test: missing arguments ---"
set +e
output=$(bash "$ELAPSED_TIME" 2>&1)
rc=$?
set -e
assert_exit "missing args returns non-zero" 1 "$rc" "$output"

echo ""
echo "=== elapsed_time: $pass passed, $fail failed ==="
[ "$fail" -eq 0 ] || exit 1
