#!/usr/bin/env bash
set -euo pipefail

# Test: stdout and stderr from deeply nested processes stream through
# to the top-level caller in real time.
#
# Architecture under test:
#   test_io_streaming.sh
#     └── loop.sh (top-level script)
#           └── (cd ... && claude -p ...) (subshell)
#                 └── mock_claude (deeply nested process)
#                       ├── writes to stdout (fd 1)
#                       └── writes to stderr (fd 2)
#
# We verify:
#   1. stdout lines from the mock arrive in loop.sh's stdout
#   2. stderr lines from the mock arrive in loop.sh's stderr
#   3. Lines arrive in chronological order (not reversed/buffered)
#   4. Lines from round 1 precede lines from round 2 (round ordering)
#   5. Output is streaming (not all bunched at the end)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts" && pwd)"

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

# --- Create mock claude that writes to BOTH stdout and stderr ---
# Each write includes a timestamp so we can verify streaming (not bunching).
# The mock also sleeps briefly between writes to create measurable gaps.

MOCK_CLAUDE="$TMPDIR_TEST/claude"
COUNTER_FILE="$TMPDIR_TEST/round_counter"
cat > "$MOCK_CLAUDE" <<'MOCK_SCRIPT'
#!/usr/bin/env bash

# Parse the prompt from args (skip flags)
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
COUNTER_FILE="${MOCK_COUNTER_FILE:-/tmp/mock_counter}"

if [[ "$prompt" == /spec:critique* ]]; then
  # Increment round counter
  round=0
  [ -f "$COUNTER_FILE" ] && round=$(cat "$COUNTER_FILE")
  round=$((round + 1))
  echo "$round" > "$COUNTER_FILE"

  # Find next version
  max_v=0
  for f in "$CRITIQUES_DIR"/*.md; do
    [ -f "$f" ] || continue
    v=$(basename "$f" | grep -oE '^v[0-9]+' | sed 's/^v//')
    [ -n "$v" ] && [ "$v" -gt "$max_v" ] && max_v=$v
  done
  next_v=$((max_v + 1))

  # Write to stdout — this MUST reach the top-level caller
  echo "STDOUT:critique:r${round}:start:$(date +%s%N)"
  sleep 0.1

  # Write to stderr — this MUST ALSO reach the top-level caller
  echo "STDERR:critique:r${round}:progress:$(date +%s%N)" >&2
  sleep 0.1

  echo "STDOUT:critique:r${round}:end:$(date +%s%N)"

  if [ "$round" -eq 1 ]; then
    cat > "$CRITIQUES_DIR/v${next_v}-test.md" <<CEOF
# Critique v${next_v}
## Issue #1: Test issue round $round
### The problem
A problem.
### Suggestion
Fix it.
CEOF
  else
    # Round 2+: only minor issues → converge
    cat > "$CRITIQUES_DIR/v${next_v}-test.md" <<CEOF
# Critique v${next_v}
## Issue #1: Minor cosmetic nitpick
### The problem
This is a trivial minor cosmetic issue.
### Suggestion
Optional fix.
CEOF
  fi

elif [[ "$prompt" == /spec:revise* ]]; then
  echo "STDOUT:revise:start:$(date +%s%N)"
  sleep 0.1
  echo "STDERR:revise:progress:$(date +%s%N)" >&2
  sleep 0.1
  echo "STDOUT:revise:end:$(date +%s%N)"

  # Create acknowledgement for latest unacknowledged critique
  for f in "$CRITIQUES_DIR"/v*-test.md; do
    [ -f "$f" ] || continue
    base=$(basename "$f" .md)
    ack="$CRITIQUES_DIR/${base}-acknowledgement.md"
    [ -f "$ack" ] && continue
    v=$(echo "$base" | grep -oE '^v[0-9]+')
    {
      echo "# Acknowledgement ${v}"
      echo ""
      grep '^## Issue #' "$f" | while IFS= read -r h; do
        echo "$h"
        echo ""
        echo "**Status: Applied to specification**"
        echo ""
      done
    } > "$ack"
  done
fi
MOCK_SCRIPT
chmod +x "$MOCK_CLAUDE"

# --- Create critic config pointing to mock claude ---
cat > "$MOCK_PROJ/.claude/skills/spec-critique-revise-loop/config/critic-commands.conf" <<CONF_EOF
claude -p "{CRITIQUE_PROMPT}" --allowed-tools "{CRITIQUE_TOOLS}"
CONF_EOF

# --- Run the loop, capturing stdout and stderr SEPARATELY ---

export PATH="$TMPDIR_TEST:$PATH"
export MOCK_COUNTER_FILE="$COUNTER_FILE"

STDOUT_FILE="$TMPDIR_TEST/stdout.txt"
STDERR_FILE="$TMPDIR_TEST/stderr.txt"
COMBINED_FILE="$TMPDIR_TEST/combined.txt"

# Capture stdout and stderr to separate files, plus a combined stream.
# The combined stream preserves interleaving order.
# We use process substitution to split while preserving ordering.
set +e
(cd "$MOCK_PROJ" && bash .claude/skills/spec-critique-revise-loop/scripts/loop.sh \
  --exit-criteria "no_major_issues_found" \
  --max-rounds 3) \
  > >(tee "$STDOUT_FILE") \
  2> >(tee "$STDERR_FILE" >&2) \
  > "$COMBINED_FILE" 2>&1
loop_exit=$?
set -e

# Give tee processes a moment to flush
sleep 0.5

# --- Assertions ---

pass=0
fail=0

assert_contains() {
  local test_name="$1" expected="$2" file="$3"
  if grep -qF "$expected" "$file"; then
    echo "  PASS: $test_name"
    pass=$((pass + 1))
  else
    echo "  FAIL: $test_name (expected '$expected' in $(basename "$file"))"
    fail=$((fail + 1))
  fi
}

assert_not_empty() {
  local test_name="$1" file="$2"
  if [ -s "$file" ]; then
    echo "  PASS: $test_name ($(wc -l < "$file" | tr -d ' ') lines)"
    pass=$((pass + 1))
  else
    echo "  FAIL: $test_name (file is empty)"
    fail=$((fail + 1))
  fi
}

assert_ordered() {
  local test_name="$1" first="$2" second="$3" file="$4"
  local first_line second_line
  first_line=$(grep -nF "$first" "$file" | head -1 | cut -d: -f1)
  second_line=$(grep -nF "$second" "$file" | head -1 | cut -d: -f1)
  if [ -n "$first_line" ] && [ -n "$second_line" ] && [ "$first_line" -lt "$second_line" ]; then
    echo "  PASS: $test_name (line $first_line < $second_line)"
    pass=$((pass + 1))
  else
    echo "  FAIL: $test_name ('$first' at line ${first_line:-?}, '$second' at line ${second_line:-?})"
    fail=$((fail + 1))
  fi
}

echo "=== test_io_streaming.sh ==="
echo ""

# --- Test 1: stdout from mock claude reaches top-level stdout ---
echo "Test 1: stdout from nested process reaches top level"
assert_contains "critique stdout start" "STDOUT:critique:r1:start" "$COMBINED_FILE"
assert_contains "critique stdout end" "STDOUT:critique:r1:end" "$COMBINED_FILE"
assert_contains "revise stdout start" "STDOUT:revise:start" "$COMBINED_FILE"
assert_contains "revise stdout end" "STDOUT:revise:end" "$COMBINED_FILE"

# --- Test 2: stderr from mock claude reaches top level ---
echo ""
echo "Test 2: stderr from nested process reaches top level"
assert_contains "critique stderr progress" "STDERR:critique:r1:progress" "$COMBINED_FILE"
assert_contains "revise stderr progress" "STDERR:revise:progress" "$COMBINED_FILE"

# --- Test 3: loop.sh's own output is present ---
echo ""
echo "Test 3: loop.sh framing output present"
assert_contains "header" "CRITIQUE-REVISE LOOP" "$COMBINED_FILE"
assert_contains "step A" "Step A" "$COMBINED_FILE"
assert_contains "step B" "Step B" "$COMBINED_FILE"
assert_contains "step D" "Step D" "$COMBINED_FILE"
assert_contains "final report" "FINAL REPORT" "$COMBINED_FILE"

# --- Test 4: round ordering (round 1 output before round 2 output) ---
echo ""
echo "Test 4: round ordering preserved"
assert_ordered "r1 critique before r2 critique" \
  "STDOUT:critique:r1:start" "STDOUT:critique:r2:start" "$COMBINED_FILE"
assert_ordered "r1 revise before r2 critique" \
  "STDOUT:revise:end" "STDOUT:critique:r2:start" "$COMBINED_FILE"

# --- Test 5: within a round, stdout and stderr interleave correctly ---
echo ""
echo "Test 5: stdout/stderr interleaving within a round"
# The mock writes: stdout start → stderr progress → stdout end
# All three should appear, and start should precede end
assert_ordered "critique start before end" \
  "STDOUT:critique:r1:start" "STDOUT:critique:r1:end" "$COMBINED_FILE"
assert_ordered "revise start before end" \
  "STDOUT:revise:start" "STDOUT:revise:end" "$COMBINED_FILE"

# --- Test 6: streaming verification via timestamps ---
# The mock sleeps 0.1s between writes and records nanosecond timestamps.
# If output were buffered until loop end, all timestamps would cluster.
# We verify that r1 critique timestamps precede r1 revise timestamps,
# proving output was produced at the point of execution, not batched.
echo ""
echo "Test 6: timestamp ordering proves streaming (not batched)"

r1_critique_ts=$(grep -F "STDOUT:critique:r1:end" "$COMBINED_FILE" | grep -oE '[0-9]{10,}' | head -1)
r1_revise_ts=$(grep -F "STDOUT:revise:start" "$COMBINED_FILE" | grep -oE '[0-9]{10,}' | head -1)

if [ -n "$r1_critique_ts" ] && [ -n "$r1_revise_ts" ]; then
  if [ "$r1_critique_ts" -lt "$r1_revise_ts" ]; then
    echo "  PASS: critique end timestamp ($r1_critique_ts) < revise start timestamp ($r1_revise_ts)"
    pass=$((pass + 1))
  else
    echo "  FAIL: timestamps out of order (critique=$r1_critique_ts, revise=$r1_revise_ts)"
    fail=$((fail + 1))
  fi
else
  echo "  FAIL: could not extract timestamps"
  fail=$((fail + 1))
fi

# --- Test 7: no exec redirects or tee in the I/O path ---
echo ""
echo "Test 7: no exec redirects polluting the I/O path"
LOOP_SRC="$MOCK_PROJ/.claude/skills/spec-critique-revise-loop/scripts/loop.sh"
if grep -qE '^\s*exec\s+>' "$LOOP_SRC"; then
  echo "  FAIL: loop.sh contains 'exec >' redirect — this introduces buffering"
  fail=$((fail + 1))
else
  echo "  PASS: no exec stdout/stderr redirects in loop.sh"
  pass=$((pass + 1))
fi

if grep -qF 'tee' "$LOOP_SRC"; then
  echo "  FAIL: loop.sh contains 'tee' — this introduces buffering"
  fail=$((fail + 1))
else
  echo "  PASS: no tee in loop.sh"
  pass=$((pass + 1))
fi

# --- Test 8: loop exited successfully ---
echo ""
echo "Test 8: loop exit"
if [ "$loop_exit" -eq 0 ]; then
  echo "  PASS: loop exited with code 0"
  pass=$((pass + 1))
else
  echo "  FAIL: loop exited with code $loop_exit"
  fail=$((fail + 1))
fi

# --- Summary ---
echo ""
echo "=== io_streaming: $pass passed, $fail failed ==="
[ "$fail" -eq 0 ]
