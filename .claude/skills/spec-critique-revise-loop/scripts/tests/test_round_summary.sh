#!/usr/bin/env bash
set -euo pipefail

# Unit tests for round_summary.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROUND_SUMMARY="$SCRIPT_DIR/round_summary.sh"
TMPDIR_TEST=$(mktemp -d)
trap 'rm -rf "$TMPDIR_TEST"' EXIT

pass=0
fail=0

assert_contains() {
  local test_name="$1"
  local expected_substr="$2"
  local actual="$3"

  if echo "$actual" | grep -qF "$expected_substr"; then
    echo "  PASS: $test_name"
    pass=$((pass + 1))
  else
    echo "  FAIL: $test_name (expected to contain '$expected_substr')"
    echo "        actual: $actual"
    fail=$((fail + 1))
  fi
}

assert_line_count() {
  local test_name="$1"
  local expected="$2"
  local actual_output="$3"

  local actual_count
  actual_count=$(echo "$actual_output" | wc -l | tr -d ' ')

  if [ "$actual_count" -eq "$expected" ]; then
    echo "  PASS: $test_name ($actual_count lines)"
    pass=$((pass + 1))
  else
    echo "  FAIL: $test_name (expected $expected lines, got $actual_count)"
    echo "        output: $actual_output"
    fail=$((fail + 1))
  fi
}

echo "=== test_round_summary.sh ==="
echo ""

# --- Test 1: Standard acknowledgement (3 applied, 0 partial, 2 skipped) ---
echo "Test 1: Real-world acknowledgement format"
cat > "$TMPDIR_TEST/ack_standard.md" <<'EOF'
# CXDB Graph UI Spec — Critique v4 (opus) Acknowledgement

3 of 5 issues were applied.

## Issue #1: Missing error handling

**Status: Applied to specification**

Fixed the error handling in the spec.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Added error handling section

## Issue #2: Incomplete API docs

**Status: Not addressed**

Out of scope for this revision.

## Issue #3: SSE docs

**Status: Applied to specification**

Added SSE documentation.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Section 10

## Issue #4: Active sessions fields

**Status: Partially addressed**

Added some fields but not all.

## Issue #5: Discovery algorithm

**Status: Applied to specification**

Rewrote discovery algorithm.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Section 5.5
EOF

output=$("$ROUND_SUMMARY" "$TMPDIR_TEST/ack_standard.md")
echo "$output"
echo ""
assert_contains "has applied symbol" "✓" "$output"
assert_contains "has skipped symbol" "✗" "$output"
assert_contains "has partial symbol" "~" "$output"
assert_contains "totals line" "Issues: 5" "$output"
assert_contains "applied count" "Applied: 3" "$output"
assert_contains "partial count" "Partial: 1" "$output"
assert_contains "skipped count" "Skipped: 1" "$output"
# 5 issue lines + 1 totals line = 6 lines
assert_line_count "6 output lines" 6 "$output"

# --- Test 2: All applied ---
echo ""
echo "Test 2: All applied"
cat > "$TMPDIR_TEST/ack_all_applied.md" <<'EOF'
# Acknowledgement

## Issue #1: Foo

**Status: Applied to specification**

Done.

## Issue #2: Bar

**Status: Applied to specification**

Done.
EOF

output=$("$ROUND_SUMMARY" "$TMPDIR_TEST/ack_all_applied.md")
echo "$output"
echo ""
assert_contains "all applied totals" "Issues: 2 | Applied: 2 | Partial: 0 | Skipped: 0" "$output"

# --- Test 3: Multiple acknowledgement files ---
echo ""
echo "Test 3: Multiple files"
cat > "$TMPDIR_TEST/ack_a.md" <<'EOF'
## Issue #1: Alpha

**Status: Applied to specification**

Done.
EOF

cat > "$TMPDIR_TEST/ack_b.md" <<'EOF'
## Issue #1: Beta

**Status: Not addressed**

Skipped.
EOF

output=$("$ROUND_SUMMARY" "$TMPDIR_TEST/ack_a.md" "$TMPDIR_TEST/ack_b.md")
echo "$output"
echo ""
assert_contains "multi-file totals" "Issues: 2 | Applied: 1 | Partial: 0 | Skipped: 1" "$output"

# --- Test 4: No arguments → usage error ---
echo ""
echo "Test 4: No arguments"
set +e
output=$("$ROUND_SUMMARY" 2>&1)
code=$?
set -e
if [ "$code" -ne 0 ]; then
  echo "  PASS: no args → non-zero exit ($code)"
  pass=$((pass + 1))
else
  echo "  FAIL: no args should fail"
  fail=$((fail + 1))
fi

# --- Test 5: Verify against real repo ack file ---
echo ""
echo "Test 5: Real v4-opus-acknowledgement.md"
real_ack="$SCRIPT_DIR/../../../specification/critiques/v4-opus-acknowledgement.md"
if [ -f "$real_ack" ]; then
  output=$("$ROUND_SUMMARY" "$real_ack")
  echo "$output"
  echo ""
  assert_contains "real file totals" "Issues: 5" "$output"
  assert_contains "real file applied" "Applied: 3" "$output"
  assert_contains "real file skipped" "Skipped: 2" "$output"
else
  echo "  SKIP: $real_ack not found"
fi

# --- Summary ---
echo ""
echo "=== round_summary.sh: $pass passed, $fail failed ==="
[ "$fail" -eq 0 ]
