#!/usr/bin/env bash
set -euo pipefail

# Tests for pre-loop unacknowledged critique processing.
#
# When loop.sh starts, if there are critique files without corresponding
# acknowledgement files, it should run /spec:revise before starting the
# main critique-revise loop.
#
# Tests:
#   1. No unacknowledged critiques → loop runs normally, no pre-loop revise
#   2. One unacknowledged critique → revise runs first, then loop
#   3. Multiple unacknowledged critiques → revise runs once for all, then loop
#   4. Pre-existing critiques that are already acknowledged → not re-processed

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts" && pwd)"
LOOP_SH="$SCRIPT_DIR/loop.sh"

TMPDIR_TEST=$(mktemp -d)
trap 'rm -rf "$TMPDIR_TEST"' EXIT

# --- Set up mock project ---

MOCK_PROJ="$TMPDIR_TEST/project"
mkdir -p "$MOCK_PROJ/.claude/skills/spec-critique-revise-loop/scripts"
mkdir -p "$MOCK_PROJ/.claude/skills/spec-critique-revise-loop/config"
mkdir -p "$MOCK_PROJ/specification-critiques"

cp "$SCRIPT_DIR/loop.sh" "$MOCK_PROJ/.claude/skills/spec-critique-revise-loop/scripts/"
cp "$SCRIPT_DIR/check_exit.sh" "$MOCK_PROJ/.claude/skills/spec-critique-revise-loop/scripts/"
cp "$SCRIPT_DIR/round_summary.sh" "$MOCK_PROJ/.claude/skills/spec-critique-revise-loop/scripts/"
cp "$SCRIPT_DIR/elapsed_time.sh" "$MOCK_PROJ/.claude/skills/spec-critique-revise-loop/scripts/"
chmod +x "$MOCK_PROJ/.claude/skills/spec-critique-revise-loop/scripts/"*.sh

# Shared invocation log so tests can inspect what mock claude was called with
INVOCATION_LOG="$TMPDIR_TEST/invocations.log"
touch "$INVOCATION_LOG"

# --- Create mock claude ---
# Behaviour:
#   /spec:critique → creates a no-issues critique (so loop converges immediately)
#   /spec:revise   → creates acknowledgement files for all unacked critiques,
#                    logs "revise:<timestamp>" to INVOCATION_LOG

MOCK_CLAUDE="$TMPDIR_TEST/claude"
COUNTER_FILE="$TMPDIR_TEST/round_counter"
cat > "$MOCK_CLAUDE" <<'MOCK_EOF'
#!/usr/bin/env bash
# Mock claude for preloop unacked tests

prompt=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -p|--print) shift ;;
    --allowed-tools|--allowedTools) shift; shift ;;
    -*) shift ;;
    *) [ -z "$prompt" ] && prompt="$1"; shift ;;
  esac
done

CRITIQUES_DIR="specification-critiques"
INVOCATION_LOG="${MOCK_INVOCATION_LOG:-/tmp/mock_invocations.log}"
COUNTER_FILE="${MOCK_COUNTER_FILE:-/tmp/mock_preloop_counter}"

if [[ "$prompt" == /spec:critique* ]]; then
  # Always produce a no-issues critique so the loop converges immediately
  round=0
  [ -f "$COUNTER_FILE" ] && round=$(cat "$COUNTER_FILE")
  round=$((round + 1))
  echo "$round" > "$COUNTER_FILE"

  max_v=0
  for f in "$CRITIQUES_DIR"/*.md; do
    [ -f "$f" ] || continue
    v=$(basename "$f" | grep -oE '^v[0-9]+' | sed 's/^v//')
    [ -n "$v" ] && [ "$v" -gt "$max_v" ] && max_v=$v
  done
  next_v=$((max_v + 1))

  cat > "$CRITIQUES_DIR/v${next_v}-test.md" <<CEOF
# Critique v${next_v} (test)

**Critic:** test
**Date:** 2026-01-01

## Prior Context

No issues from previous round.

---

No significant issues found. The spec is solid.
CEOF
  echo "Critique v${next_v} created with no issues."
  echo "=== CRITIQUE SKILL COMPLETE ==="

elif [[ "$prompt" == /spec:revise* ]]; then
  # Log pre-loop vs loop revise calls by checking if the loop has started.
  # The round counter file is created on the FIRST critique call; if it
  # exists at revise time, we are inside the loop (not pre-loop).
  if [ -f "$COUNTER_FILE" ]; then
    echo "loop_revise:$(date +%s)" >> "$INVOCATION_LOG"
  else
    echo "preloop_revise:$(date +%s)" >> "$INVOCATION_LOG"
  fi

  # Create acknowledgement files for all unacked critiques
  for f in "$CRITIQUES_DIR"/v*-*.md; do
    [ -f "$f" ] || continue
    [[ "$f" == *acknowledgement* ]] && continue
    base=$(basename "$f" .md)
    ack="$CRITIQUES_DIR/${base}-acknowledgement.md"
    [ -f "$ack" ] && continue
    cat > "$ack" <<AEOF
# Acknowledgement for $base

All issues acknowledged.

**Status: Applied to specification**
AEOF
  done
  echo "Pre-loop revise complete."
  echo "=== REVISE SKILL COMPLETE ==="

else
  echo "Mock claude: unknown prompt: $prompt"
  exit 1
fi
MOCK_EOF
chmod +x "$MOCK_CLAUDE"

# Critic config: single test critic
cat > "$MOCK_PROJ/.claude/skills/spec-critique-revise-loop/config/critic-commands.conf" <<'CONF_EOF'
claude -p "{CRITIQUE_PROMPT}" --allowed-tools "{CRITIQUE_TOOLS}"
CONF_EOF

export PATH="$TMPDIR_TEST:$PATH"
export MOCK_INVOCATION_LOG="$INVOCATION_LOG"
export MOCK_COUNTER_FILE="$COUNTER_FILE"

# --- Test helpers ---

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

assert_contains() {
  local test_name="$1" expected="$2" actual="$3"
  if echo "$actual" | grep -qF "$expected"; then
    echo "  PASS: $test_name"
    pass=$((pass + 1))
  else
    echo "  FAIL: $test_name (expected to contain '$expected')"
    fail=$((fail + 1))
  fi
}

assert_not_contains() {
  local test_name="$1" unexpected="$2" actual="$3"
  if echo "$actual" | grep -qF "$unexpected"; then
    echo "  FAIL: $test_name (expected NOT to contain '$unexpected')"
    fail=$((fail + 1))
  else
    echo "  PASS: $test_name"
    pass=$((pass + 1))
  fi
}

assert_file_exists() {
  local test_name="$1" file="$2"
  if [ -f "$file" ]; then
    echo "  PASS: $test_name"
    pass=$((pass + 1))
  else
    echo "  FAIL: $test_name (file not found: $file)"
    fail=$((fail + 1))
  fi
}

assert_file_not_exists() {
  local test_name="$1" file="$2"
  if [ ! -f "$file" ]; then
    echo "  PASS: $test_name"
    pass=$((pass + 1))
  else
    echo "  FAIL: $test_name (file should not exist: $file)"
    fail=$((fail + 1))
  fi
}

count_lines() {
  local file="$1"
  [ -f "$file" ] && wc -l < "$file" | tr -d ' ' || echo 0
}

echo "=== test_preloop_unacked.sh ==="
echo ""

# ===========================================================================
# Test 1: No unacknowledged critiques — loop runs normally, no pre-loop revise
# ===========================================================================

echo "--- Test 1: No unacknowledged critiques ---"

# Clean state
rm -f "$INVOCATION_LOG" "$COUNTER_FILE"
touch "$INVOCATION_LOG"
rm -f "$MOCK_PROJ/specification-critiques/"* 2>/dev/null || true

set +e
output1=$(cd "$MOCK_PROJ" && bash .claude/skills/spec-critique-revise-loop/scripts/loop.sh \
  --exit-criteria "no_major_issues_found" \
  --max-rounds 1 2>&1)
exit1=$?
set -e

assert_eq "test1: exit code 0" "0" "$exit1"
assert_not_contains "test1: no pre-loop revise message" "Found " "$output1"

# No pre-loop revise (no unacked critiques), but loop revise runs on convergence
preloop_revise_count1=$(awk '/^preloop_revise:/{c++} END{print c+0}' "$INVOCATION_LOG" 2>/dev/null)
loop_revise_count1=$(awk '/^loop_revise:/{c++} END{print c+0}' "$INVOCATION_LOG" 2>/dev/null)
assert_eq "test1: no pre-loop revise calls" "0" "$preloop_revise_count1"
assert_eq "test1: loop revise ran once (on convergence)" "1" "$loop_revise_count1"

echo ""

# ===========================================================================
# Test 2: One unacknowledged critique — revise runs before the loop
# ===========================================================================

echo "--- Test 2: One unacknowledged critique ---"

# Clean state
rm -f "$INVOCATION_LOG" "$COUNTER_FILE"
touch "$INVOCATION_LOG"
rm -f "$MOCK_PROJ/specification-critiques/"* 2>/dev/null || true

# Plant one unacknowledged critique
cat > "$MOCK_PROJ/specification-critiques/v1-previous.md" <<'EOF'
# Critique v1 (previous session)

**Critic:** test
**Date:** 2026-01-01

## Prior Context

From a previous session.

---

## Issue #1: Something was wrong

### The problem
A problem from before.

### Suggestion
Fix it.
EOF

set +e
output2=$(cd "$MOCK_PROJ" && bash .claude/skills/spec-critique-revise-loop/scripts/loop.sh \
  --exit-criteria "no_major_issues_found" \
  --max-rounds 1 2>&1)
exit2=$?
set -e

assert_eq "test2: exit code 0" "0" "$exit2"
assert_contains "test2: reports 1 unacknowledged critique" "1 unacknowledged" "$output2"
assert_contains "test2: names the file" "v1-previous.md" "$output2"
assert_contains "test2: says running revise" "Running /spec:revise" "$output2"

# Pre-loop revise ran once; loop revise also ran once on convergence
preloop_revise_count2=$(awk '/^preloop_revise:/{c++} END{print c+0}' "$INVOCATION_LOG" 2>/dev/null)
loop_revise_count2=$(awk '/^loop_revise:/{c++} END{print c+0}' "$INVOCATION_LOG" 2>/dev/null)
assert_eq "test2: pre-loop revise called once" "1" "$preloop_revise_count2"
assert_eq "test2: loop revise ran once (on convergence)" "1" "$loop_revise_count2"

# Acknowledgement file created for the pre-existing critique
assert_file_exists "test2: ack created for v1-previous" \
  "$MOCK_PROJ/specification-critiques/v1-previous-acknowledgement.md"

echo ""

# ===========================================================================
# Test 3: Multiple unacknowledged critiques — revise runs once for all
# ===========================================================================

echo "--- Test 3: Multiple unacknowledged critiques ---"

# Clean state
rm -f "$INVOCATION_LOG" "$COUNTER_FILE"
touch "$INVOCATION_LOG"
rm -f "$MOCK_PROJ/specification-critiques/"* 2>/dev/null || true

# Plant two unacknowledged critiques
cat > "$MOCK_PROJ/specification-critiques/v3-alpha.md" <<'EOF'
# Critique v3

**Critic:** alpha
**Date:** 2026-01-01

---

## Issue #1: Alpha problem

### The problem
Alpha issue.

### Suggestion
Fix alpha.
EOF

cat > "$MOCK_PROJ/specification-critiques/v3-beta.md" <<'EOF'
# Critique v3

**Critic:** beta
**Date:** 2026-01-01

---

## Issue #1: Beta problem

### The problem
Beta issue.

### Suggestion
Fix beta.
EOF

set +e
output3=$(cd "$MOCK_PROJ" && bash .claude/skills/spec-critique-revise-loop/scripts/loop.sh \
  --exit-criteria "no_major_issues_found" \
  --max-rounds 1 2>&1)
exit3=$?
set -e

assert_eq "test3: exit code 0" "0" "$exit3"
assert_contains "test3: reports 2 unacknowledged critiques" "2 unacknowledged" "$output3"

# Pre-loop revise ran once (not once per file); loop revise also ran on convergence
preloop_revise_count3=$(awk '/^preloop_revise:/{c++} END{print c+0}' "$INVOCATION_LOG" 2>/dev/null)
loop_revise_count3=$(awk '/^loop_revise:/{c++} END{print c+0}' "$INVOCATION_LOG" 2>/dev/null)
assert_eq "test3: pre-loop revise called exactly once (not per-file)" "1" "$preloop_revise_count3"
assert_eq "test3: loop revise ran once (on convergence)" "1" "$loop_revise_count3"

# Both ack files created
assert_file_exists "test3: ack created for v3-alpha" \
  "$MOCK_PROJ/specification-critiques/v3-alpha-acknowledgement.md"
assert_file_exists "test3: ack created for v3-beta" \
  "$MOCK_PROJ/specification-critiques/v3-beta-acknowledgement.md"

echo ""

# ===========================================================================
# Test 4: Already-acknowledged critiques are NOT re-processed
# ===========================================================================

echo "--- Test 4: Already-acknowledged critiques skipped ---"

# Clean state
rm -f "$INVOCATION_LOG" "$COUNTER_FILE"
touch "$INVOCATION_LOG"
rm -f "$MOCK_PROJ/specification-critiques/"* 2>/dev/null || true

# Plant one acknowledged critique (both files exist)
cat > "$MOCK_PROJ/specification-critiques/v5-done.md" <<'EOF'
# Critique v5

**Critic:** done
**Date:** 2026-01-01

---

No issues.
EOF
cat > "$MOCK_PROJ/specification-critiques/v5-done-acknowledgement.md" <<'EOF'
# Acknowledgement for v5-done

All done.
EOF

set +e
output4=$(cd "$MOCK_PROJ" && bash .claude/skills/spec-critique-revise-loop/scripts/loop.sh \
  --exit-criteria "no_major_issues_found" \
  --max-rounds 1 2>&1)
exit4=$?
set -e

assert_eq "test4: exit code 0" "0" "$exit4"
assert_not_contains "test4: no pre-loop revise triggered" "Found " "$output4"

# No pre-loop revise (all critiques acknowledged), but loop revise runs on convergence
preloop_revise_count4=$(awk '/^preloop_revise:/{c++} END{print c+0}' "$INVOCATION_LOG" 2>/dev/null)
loop_revise_count4=$(awk '/^loop_revise:/{c++} END{print c+0}' "$INVOCATION_LOG" 2>/dev/null)
assert_eq "test4: no pre-loop revise calls" "0" "$preloop_revise_count4"
assert_eq "test4: loop revise ran once (on convergence)" "1" "$loop_revise_count4"

echo ""

# ===========================================================================
# Test 5: Pre-loop revise output appears before round 1
# ===========================================================================

echo "--- Test 5: Pre-loop revise output appears before loop ---"

# Clean state
rm -f "$INVOCATION_LOG" "$COUNTER_FILE"
touch "$INVOCATION_LOG"
rm -f "$MOCK_PROJ/specification-critiques/"* 2>/dev/null || true

# Plant one unacknowledged critique
cat > "$MOCK_PROJ/specification-critiques/v7-prior.md" <<'EOF'
# Critique v7 (prior)

**Critic:** test
**Date:** 2026-01-01

---

## Issue #1: Prior issue

### The problem
Prior problem.

### Suggestion
Fix it.
EOF

set +e
output5=$(cd "$MOCK_PROJ" && bash .claude/skills/spec-critique-revise-loop/scripts/loop.sh \
  --exit-criteria "no_major_issues_found" \
  --max-rounds 1 2>&1)
exit5=$?
set -e

# The unacknowledged message should appear before "Step A (round 1"
pre_loop_pos=$(echo "$output5" | grep -n "unacknowledged" | head -1 | cut -d: -f1 || true)
round1_pos=$(echo "$output5" | grep -n "Step A (round 1" | head -1 | cut -d: -f1 || true)

if [ -n "$pre_loop_pos" ] && [ -n "$round1_pos" ] && [ "$pre_loop_pos" -lt "$round1_pos" ]; then
  echo "  PASS: test5: pre-loop revise output precedes round 1"
  pass=$((pass + 1))
else
  echo "  FAIL: test5: pre-loop revise output should precede round 1"
  echo "        pre_loop_pos=$pre_loop_pos round1_pos=$round1_pos"
  fail=$((fail + 1))
fi

echo ""

# --- Summary ---

echo "=== preloop_unacked: $pass passed, $fail failed ==="
[ "$fail" -eq 0 ]
