#!/usr/bin/env bash
set -euo pipefail

# Unit tests for check_exit.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts" && pwd)"
CHECK_EXIT="$SCRIPT_DIR/check_exit.sh"
TMPDIR_TEST=$(mktemp -d)
trap 'rm -rf "$TMPDIR_TEST"' EXIT

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

echo "=== test_check_exit.sh ==="
echo ""

# --- Test 1: No issues → converged (exit 1) ---
echo "Test 1: No issues found"
cat > "$TMPDIR_TEST/critique_no_issues.md" <<'EOF'
# Critique v99

**Critic:** test
**Date:** 2026-01-01

## Prior Context

Nothing.

---

No significant issues were found. The spec looks solid.
EOF

set +e
output=$("$CHECK_EXIT" "$TMPDIR_TEST/critique_no_issues.md" "no_issues_found")
code=$?
set -e
assert_exit "no issues → converged" 1 "$code" "$output"
assert_contains "no issues → message" "CONVERGED" "$output"

# --- Test 2: Major issues → continue (exit 0) ---
echo ""
echo "Test 2: Major issues found"
cat > "$TMPDIR_TEST/critique_major.md" <<'EOF'
# Critique v99

## Issue #1: Missing error handling

### The problem
The spec does not handle errors.

### Suggestion
Add error handling.

## Issue #2: Incomplete API docs

### The problem
API docs are incomplete.

### Suggestion
Complete the API docs.
EOF

prev_file="$TMPDIR_TEST/prev_issues.txt"
rm -f "$prev_file"

set +e
output=$("$CHECK_EXIT" "$TMPDIR_TEST/critique_major.md" "no_major_issues_found" "$prev_file")
code=$?
set -e
assert_exit "major issues → continue" 0 "$code" "$output"
assert_contains "major issues → message" "CONTINUE" "$output"
assert_contains "major issues → count" "2 issue(s)" "$output"

# --- Test 3: All minor issues with no_major_issues_found → converged (exit 1) ---
echo ""
echo "Test 3: All minor issues"
cat > "$TMPDIR_TEST/critique_all_minor.md" <<'EOF'
# Critique v99

## Issue #1: Typo in section header

### The problem
This is a minor cosmetic issue — a typo in a heading.

### Suggestion
Fix the typo.

## Issue #2: Inconsistent formatting

### The problem
This is a trivial nitpick about formatting.

### Suggestion
Fix formatting.
EOF

set +e
output=$("$CHECK_EXIT" "$TMPDIR_TEST/critique_all_minor.md" "no_major_issues_found")
code=$?
set -e
assert_exit "all minor → converged" 1 "$code" "$output"
assert_contains "all minor → message" "CONVERGED" "$output"
assert_contains "all minor → minor" "minor" "$output"

# --- Test 4: All minor with no_issues_found → continue (exit 0) ---
echo ""
echo "Test 4: All minor issues but strict criteria"
prev_file2="$TMPDIR_TEST/prev_issues2.txt"
rm -f "$prev_file2"

set +e
output=$("$CHECK_EXIT" "$TMPDIR_TEST/critique_all_minor.md" "no_issues_found" "$prev_file2")
code=$?
set -e
assert_exit "all minor + strict → continue" 0 "$code" "$output"
assert_contains "all minor + strict → message" "CONTINUE" "$output"

# --- Test 5: Mixed major/minor → continue (exit 0) ---
echo ""
echo "Test 5: Mixed major and minor issues"
cat > "$TMPDIR_TEST/critique_mixed.md" <<'EOF'
# Critique v99

## Issue #1: Critical design flaw

### The problem
The architecture is fundamentally wrong.

### Suggestion
Redesign.

## Issue #2: Small typo

### The problem
This is a minor nitpick.

### Suggestion
Fix it.
EOF

prev_file3="$TMPDIR_TEST/prev_issues3.txt"
rm -f "$prev_file3"

set +e
output=$("$CHECK_EXIT" "$TMPDIR_TEST/critique_mixed.md" "no_major_issues_found" "$prev_file3")
code=$?
set -e
assert_exit "mixed → continue" 0 "$code" "$output"

# --- Test 6: Stuck detection (same issues twice) ---
echo ""
echo "Test 6: Stuck detection"
prev_file4="$TMPDIR_TEST/prev_issues4.txt"
rm -f "$prev_file4"

# First run: saves issues
set +e
output1=$("$CHECK_EXIT" "$TMPDIR_TEST/critique_major.md" "no_major_issues_found" "$prev_file4")
code1=$?
set -e
assert_exit "stuck round1 → continue" 0 "$code1" "$output1"

# Second run: same file → stuck
set +e
output2=$("$CHECK_EXIT" "$TMPDIR_TEST/critique_major.md" "no_major_issues_found" "$prev_file4")
code2=$?
set -e
assert_exit "stuck round2 → stuck" 2 "$code2" "$output2"
assert_contains "stuck round2 → message" "STUCK" "$output2"

# --- Test 7: Subset detection (fewer issues than before) ---
echo ""
echo "Test 7: Subset detection"
cat > "$TMPDIR_TEST/critique_subset.md" <<'EOF'
# Critique v99

## Issue #2: Incomplete API docs

### The problem
API docs are incomplete.

### Suggestion
Complete the API docs.
EOF

# prev_file4 has both "Incomplete API docs" and "Missing error handling" from test 6
set +e
output=$("$CHECK_EXIT" "$TMPDIR_TEST/critique_subset.md" "no_major_issues_found" "$prev_file4")
code=$?
set -e
assert_exit "subset → stuck" 2 "$code" "$output"

# --- Test 8: New issues after previous round → continue ---
echo ""
echo "Test 8: New issues not stuck"
cat > "$TMPDIR_TEST/critique_new.md" <<'EOF'
# Critique v99

## Issue #1: Brand new problem

### The problem
This is totally new.

### Suggestion
Fix it.
EOF

set +e
output=$("$CHECK_EXIT" "$TMPDIR_TEST/critique_new.md" "no_major_issues_found" "$prev_file4")
code=$?
set -e
assert_exit "new issues → continue" 0 "$code" "$output"

# --- Test 9: Missing file → exit 3 ---
echo ""
echo "Test 9: Missing critique file"
set +e
output=$("$CHECK_EXIT" "$TMPDIR_TEST/nonexistent.md" "no_issues_found")
code=$?
set -e
assert_exit "missing file → exit 3" 3 "$code" "$output"

# --- Summary ---
echo ""
echo "=== check_exit.sh: $pass passed, $fail failed ==="
[ "$fail" -eq 0 ]
