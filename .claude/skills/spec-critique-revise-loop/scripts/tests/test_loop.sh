#!/usr/bin/env bash
set -euo pipefail

# Integration test for loop.sh using a mock 'claude' command.
#
# The mock claude:
#   - On /spec:critique: creates a critique file with decreasing issues per round
#   - On /spec:revise: creates an acknowledgement file for the latest critique
#
# This validates the full loop flow without hitting the real Claude API.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOOP_SH="$SCRIPT_DIR/loop.sh"

# Create a temp project directory that mirrors the real structure
TMPDIR_TEST=$(mktemp -d)
trap 'rm -rf "$TMPDIR_TEST"' EXIT

MOCK_PROJ="$TMPDIR_TEST/project"
mkdir -p "$MOCK_PROJ/.claude/skills/spec-critique-revise-loop/scripts"
mkdir -p "$MOCK_PROJ/specification/critiques"

# Copy the real scripts into the mock project
cp "$SCRIPT_DIR/loop.sh" "$MOCK_PROJ/.claude/skills/spec-critique-revise-loop/scripts/"
cp "$SCRIPT_DIR/check_exit.sh" "$MOCK_PROJ/.claude/skills/spec-critique-revise-loop/scripts/"
cp "$SCRIPT_DIR/round_summary.sh" "$MOCK_PROJ/.claude/skills/spec-critique-revise-loop/scripts/"
chmod +x "$MOCK_PROJ/.claude/skills/spec-critique-revise-loop/scripts/"*.sh

# --- Create mock claude binary ---
# The mock tracks round state via a counter file.
# Round 1 critique: 3 major issues
# Round 2 critique: 1 minor issue only
# This should converge after round 2 critique with no_major_issues_found.

MOCK_CLAUDE="$TMPDIR_TEST/claude"
cat > "$MOCK_CLAUDE" <<'MOCK_EOF'
#!/usr/bin/env bash
# Mock claude -p that creates critique/ack files based on round counter

# Parse args: find the prompt (first non-flag arg after -p)
prompt=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -p|--print) shift ;;
    --allowed-tools|--allowedTools) shift; shift ;; # skip flag + value
    -*) shift ;;
    *)
      if [ -z "$prompt" ]; then
        prompt="$1"
      fi
      shift
      ;;
  esac
done

CRITIQUES_DIR="specification/critiques"
COUNTER_FILE="/tmp/mock_claude_round_counter"

if [[ "$prompt" == /spec:critique* ]]; then
  # Determine round from counter
  if [ -f "$COUNTER_FILE" ]; then
    round=$(cat "$COUNTER_FILE")
  else
    round=0
  fi
  round=$((round + 1))
  echo "$round" > "$COUNTER_FILE"

  # Find next version number
  max_v=0
  for f in "$CRITIQUES_DIR"/*.md; do
    [ -f "$f" ] || continue
    v=$(basename "$f" | grep -oE '^v[0-9]+' | sed 's/^v//')
    if [ -n "$v" ] && [ "$v" -gt "$max_v" ]; then
      max_v=$v
    fi
  done
  next_v=$((max_v + 1))

  critique_file="$CRITIQUES_DIR/v${next_v}-test.md"

  if [ "$round" -eq 1 ]; then
    cat > "$critique_file" <<CRITIQUE_EOF
# Critique v${next_v} (test)

**Critic:** test
**Date:** 2026-01-01

## Prior Context

First round.

---

## Issue #1: Missing error handling

### The problem
The spec does not handle errors properly.

### Suggestion
Add comprehensive error handling.

## Issue #2: Incomplete API surface

### The problem
Several endpoints are undocumented.

### Suggestion
Document all endpoints.

## Issue #3: Ambiguous state transitions

### The problem
State machine transitions are unclear.

### Suggestion
Add a state diagram.
CRITIQUE_EOF
    echo "Critique v${next_v} created with 3 issues."
    echo "=== CRITIQUE SKILL COMPLETE ==="

  elif [ "$round" -eq 2 ]; then
    cat > "$critique_file" <<CRITIQUE_EOF
# Critique v${next_v} (test)

**Critic:** test
**Date:** 2026-01-01

## Prior Context

Previous issues were addressed.

---

## Issue #1: Minor typo in section header

### The problem
This is a minor cosmetic nitpick — a typo in heading 3.2.

### Suggestion
Fix the typo.
CRITIQUE_EOF
    echo "Critique v${next_v} created with 1 minor issue."
    echo "=== CRITIQUE SKILL COMPLETE ==="

  else
    # Round 3+: no issues
    cat > "$critique_file" <<CRITIQUE_EOF
# Critique v${next_v} (test)

**Critic:** test
**Date:** 2026-01-01

## Prior Context

All issues resolved.

---

No significant issues found. The spec is solid.
CRITIQUE_EOF
    echo "Critique v${next_v} created with no issues."
    echo "=== CRITIQUE SKILL COMPLETE ==="
  fi

elif [[ "$prompt" == /spec:revise* ]]; then
  # Find the latest unacknowledged critique
  latest_critique=""
  for f in "$CRITIQUES_DIR"/v*-test.md; do
    [ -f "$f" ] || continue
    base=$(basename "$f" .md)
    ack_file="$CRITIQUES_DIR/${base}-acknowledgement.md"
    if [ ! -f "$ack_file" ]; then
      latest_critique="$f"
    fi
  done

  if [ -z "$latest_critique" ]; then
    echo "No unacknowledged critique found."
    exit 0
  fi

  base=$(basename "$latest_critique" .md)
  v=$(echo "$base" | grep -oE '^v[0-9]+')
  ack_file="$CRITIQUES_DIR/${base}-acknowledgement.md"

  # Count issues in critique
  issue_count=$(grep -c '^## Issue #' "$latest_critique" || echo 0)

  # Generate acknowledgement — mark all as applied
  {
    echo "# Critique ${v} (test) Acknowledgement"
    echo ""
    echo "All $issue_count issues were applied."
    echo ""

    # Extract each issue and write an Applied status
    grep '^## Issue #' "$latest_critique" | while IFS= read -r heading; do
      echo "$heading"
      echo ""
      echo "**Status: Applied to specification**"
      echo ""
      echo "Applied this change."
      echo ""
    done
  } > "$ack_file"

  echo "Acknowledgement created: $ack_file"
  echo "=== REVISE SKILL COMPLETE ==="

else
  echo "Mock claude: unknown prompt: $prompt"
  exit 1
fi
MOCK_EOF
chmod +x "$MOCK_CLAUDE"

# --- Run the test ---

echo "=== test_loop.sh ==="
echo ""
echo "Mock project: $MOCK_PROJ"
echo "Mock claude: $MOCK_CLAUDE"
echo ""

# Reset round counter
rm -f /tmp/mock_claude_round_counter

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
    echo "        searched in ${#actual} chars of output"
    fail=$((fail + 1))
  fi
}

# Test: 2-round loop with no_major_issues_found should converge after round 2
echo "--- Running loop.sh with mock claude (max 3 rounds) ---"
echo ""

# Put mock claude first in PATH
export PATH="$TMPDIR_TEST:$PATH"

set +e
output=$(cd "$MOCK_PROJ" && bash .claude/skills/spec-critique-revise-loop/scripts/loop.sh \
  --exit-criteria "no_major_issues_found" \
  --max-rounds 3 2>&1)
exit_code=$?
set -e

echo "$output"
echo ""
echo "--- End of loop output (exit code: $exit_code) ---"
echo ""

# Verify the output
assert_contains "header printed" "CRITIQUE-REVISE LOOP" "$output"
assert_contains "round 1 started" "[STEP A] round = 1 of 3" "$output"
assert_contains "round 1 critique" "[STEP B] (round 1 of 3)" "$output"
assert_contains "round 1 exit check" "[STEP D] (round 1 of 3)" "$output"
assert_contains "round 1 continue" "CONTINUE" "$output"
assert_contains "round 1 revise" "[STEP E] (round 1 of 3)" "$output"
assert_contains "round 1 summary" "[STEP F] (round 1 of 3)" "$output"
assert_contains "round 1 complete" "ROUND 1 of 3 COMPLETE" "$output"
assert_contains "round 2 started" "[STEP A] round = 2 of 3" "$output"
assert_contains "round 2 critique" "[STEP B] (round 2 of 3)" "$output"
assert_contains "converged" "CONVERGED" "$output"
assert_contains "final report" "FINAL REPORT" "$output"
assert_contains "exit reason converged" "Exit reason:       converged" "$output"
assert_contains "rounds completed" "Rounds completed:  2" "$output"

# Round 2 should NOT have revise/summary (converged at step D)
if echo "$output" | grep -qF "[STEP E] (round 2 of 3)"; then
  echo "  FAIL: round 2 should not have revise step (converged at D)"
  fail=$((fail + 1))
else
  echo "  PASS: round 2 correctly stopped at convergence"
  pass=$((pass + 1))
fi

# Verify files were created
echo ""
echo "Files in critiques dir:"
ls -la "$MOCK_PROJ/specification/critiques/"

critique_count=$(ls "$MOCK_PROJ/specification/critiques/"/*-test.md 2>/dev/null | grep -cv acknowledgement || echo 0)
ack_count=$(ls "$MOCK_PROJ/specification/critiques/"/*acknowledgement.md 2>/dev/null | wc -l | tr -d ' ')

if [ "$critique_count" -eq 2 ]; then
  echo "  PASS: 2 critique files created"
  pass=$((pass + 1))
else
  echo "  FAIL: expected 2 critique files, got $critique_count"
  fail=$((fail + 1))
fi

if [ "$ack_count" -eq 1 ]; then
  echo "  PASS: 1 acknowledgement file created (only round 1 revised)"
  pass=$((pass + 1))
else
  echo "  FAIL: expected 1 acknowledgement file, got $ack_count"
  fail=$((fail + 1))
fi

# Verify exit code
if [ "$exit_code" -eq 0 ]; then
  echo "  PASS: loop exited with code 0"
  pass=$((pass + 1))
else
  echo "  FAIL: loop exited with code $exit_code (expected 0)"
  fail=$((fail + 1))
fi

# Cleanup
rm -f /tmp/mock_claude_round_counter

echo ""
echo "=== loop.sh: $pass passed, $fail failed ==="
[ "$fail" -eq 0 ]
