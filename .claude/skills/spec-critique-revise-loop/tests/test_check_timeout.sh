#!/usr/bin/env bash
set -euo pipefail

# Unit tests for check_timeout.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts" && pwd)"
CHECK_TIMEOUT="$SCRIPT_DIR/check_timeout.sh"

pass=0
fail=0

assert_exit() {
  local test_name="$1"
  local expected_exit="$2"
  local actual_exit="$3"
  local output="$4"

  if [ "$actual_exit" -eq "$expected_exit" ]; then
    echo "  PASS: $test_name (exit=$actual_exit)"
    pass=$((pass + 1))
  else
    echo "  FAIL: $test_name (expected exit=$expected_exit, got exit=$actual_exit)"
    echo "        output: $output"
    fail=$((fail + 1))
  fi
}

assert_contains() {
  local test_name="$1"
  local expected_substr="$2"
  local actual="$3"

  if echo "$actual" | grep -qF "$expected_substr"; then
    echo "  PASS: $test_name (contains '$expected_substr')"
    pass=$((pass + 1))
  else
    echo "  FAIL: $test_name (expected to contain '$expected_substr')"
    echo "        actual: $actual"
    fail=$((fail + 1))
  fi
}

echo "=== check_timeout.sh tests ==="

# Test 1: Within time limit (started just now, 10 minute timeout)
echo ""
echo "--- Test: within time limit ---"
now=$(date +%s)
set +e
output=$(bash "$CHECK_TIMEOUT" "$now" 10 "test-label" 2>&1)
rc=$?
set -e
assert_exit "within time limit returns 0" 0 "$rc" "$output"
assert_contains "prints OK" "OK" "$output"
assert_contains "includes label" "test-label" "$output"
assert_contains "shows remaining" "remaining" "$output"

# Test 2: Timeout exceeded (started 20 minutes ago, 10 minute timeout)
echo ""
echo "--- Test: timeout exceeded ---"
past=$(( $(date +%s) - 1200 ))  # 20 minutes ago
set +e
output=$(bash "$CHECK_TIMEOUT" "$past" 10 "my-timeout" 2>&1)
rc=$?
set -e
assert_exit "exceeded returns 1" 1 "$rc" "$output"
assert_contains "prints TIMEOUT" "TIMEOUT" "$output"
assert_contains "includes label" "my-timeout" "$output"

# Test 3: Exactly at the boundary (started exactly N minutes ago)
echo ""
echo "--- Test: exactly at boundary ---"
boundary=$(( $(date +%s) - 300 ))  # exactly 5 minutes ago
set +e
output=$(bash "$CHECK_TIMEOUT" "$boundary" 5 "boundary" 2>&1)
rc=$?
set -e
assert_exit "at boundary returns 1" 1 "$rc" "$output"

# Test 4: Well before boundary (2 seconds of slack to avoid races)
echo ""
echo "--- Test: before boundary ---"
almost=$(( $(date +%s) - 298 ))  # 4m58s ago, 2s slack
set +e
output=$(bash "$CHECK_TIMEOUT" "$almost" 5 "almost" 2>&1)
rc=$?
set -e
assert_exit "before boundary returns 0" 0 "$rc" "$output"

# Test 5: Zero timeout (should immediately timeout)
echo ""
echo "--- Test: zero timeout ---"
set +e
output=$(bash "$CHECK_TIMEOUT" "$(( $(date +%s) - 1 ))" 0 "zero" 2>&1)
rc=$?
set -e
assert_exit "zero timeout returns 1" 1 "$rc" "$output"

# Test 6: Large timeout (should be within limit)
echo ""
echo "--- Test: large timeout ---"
set +e
output=$(bash "$CHECK_TIMEOUT" "$(date +%s)" 9999 "large" 2>&1)
rc=$?
set -e
assert_exit "large timeout returns 0" 0 "$rc" "$output"

# Test 7: Default label when omitted
echo ""
echo "--- Test: default label ---"
set +e
output=$(bash "$CHECK_TIMEOUT" "$(date +%s)" 10 2>&1)
rc=$?
set -e
assert_exit "default label returns 0" 0 "$rc" "$output"
assert_contains "uses default label" "timeout" "$output"

# Test 8: Missing arguments
echo ""
echo "--- Test: missing arguments ---"
set +e
output=$(bash "$CHECK_TIMEOUT" 2>&1)
rc=$?
set -e
assert_exit "missing args returns non-zero" 1 "$rc" "$output"

echo ""
echo "=== Results: $pass passed, $fail failed ==="
[ "$fail" -eq 0 ] || exit 1
