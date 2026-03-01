#!/usr/bin/env bash
set -euo pipefail

# Integration test for round.sh — the per-round script.
#
# Tests:
#   1. Round 1 with major issues → exit 0 (continue)
#   2. Round 2 with all-minor issues → exit 1 (converged)
#   3. State persistence between rounds via state dir
#   4. Report generation from state dir

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts" && pwd)"

TMPDIR_TEST=$(mktemp -d)
trap 'rm -rf "$TMPDIR_TEST"' EXIT

# --- Set up mock project ---

MOCK_PROJ="$TMPDIR_TEST/project"
mkdir -p "$MOCK_PROJ/.claude/skills/spec-critique-revise-loop/scripts"
mkdir -p "$MOCK_PROJ/.claude/skills/spec-critique-revise-loop/config"
mkdir -p "$MOCK_PROJ/specification-critiques"

cp "$SCRIPT_DIR/round.sh" "$MOCK_PROJ/.claude/skills/spec-critique-revise-loop/scripts/"
cp "$SCRIPT_DIR/check_exit.sh" "$MOCK_PROJ/.claude/skills/spec-critique-revise-loop/scripts/"
cp "$SCRIPT_DIR/round_summary.sh" "$MOCK_PROJ/.claude/skills/spec-critique-revise-loop/scripts/"
cp "$SCRIPT_DIR/report.sh" "$MOCK_PROJ/.claude/skills/spec-critique-revise-loop/scripts/"
cp "$SCRIPT_DIR/elapsed_time.sh" "$MOCK_PROJ/.claude/skills/spec-critique-revise-loop/scripts/"
chmod +x "$MOCK_PROJ/.claude/skills/spec-critique-revise-loop/scripts/"*.sh

# --- Create mock claude ---

MOCK_CLAUDE="$TMPDIR_TEST/claude"
COUNTER_FILE="$TMPDIR_TEST/round_counter"
cat > "$MOCK_CLAUDE" <<'MOCK_SCRIPT'
#!/usr/bin/env bash

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

  if [ "$round" -eq 1 ]; then
    cat > "$CRITIQUES_DIR/v${next_v}-test.md" <<CEOF
# Critique v${next_v}
## Issue #1: Major problem round $round
### The problem
A serious problem.
### Suggestion
Fix it properly.

## Issue #2: Another major issue
### The problem
Another serious problem.
### Suggestion
Fix this too.
CEOF
    echo "Critique with 2 major issues."
  else
    cat > "$CRITIQUES_DIR/v${next_v}-test.md" <<CEOF
# Critique v${next_v}
## Issue #1: Minor cosmetic nitpick
### The problem
This is a trivial minor cosmetic issue.
### Suggestion
Optional fix.
CEOF
    echo "Critique with 1 minor issue."
  fi

elif [[ "$prompt" == /spec:revise* ]]; then
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
  echo "Revise complete."
fi
MOCK_SCRIPT
chmod +x "$MOCK_CLAUDE"

# --- Create critic config pointing to mock claude ---
cat > "$MOCK_PROJ/.claude/skills/spec-critique-revise-loop/config/critic-commands.conf" <<CONF_EOF
claude -p "{CRITIQUE_PROMPT}" --allowed-tools "{CRITIQUE_TOOLS}"
CONF_EOF

# --- Test helpers ---

export PATH="$TMPDIR_TEST:$PATH"
export MOCK_COUNTER_FILE="$COUNTER_FILE"

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

assert_matches() {
  local test_name="$1" pattern="$2" actual="$3"
  if echo "$actual" | grep -qE "$pattern"; then
    echo "  PASS: $test_name"
    pass=$((pass + 1))
  else
    echo "  FAIL: $test_name (expected to match '$pattern')"
    fail=$((fail + 1))
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

echo "=== test_round.sh ==="
echo ""

STATE_DIR="$TMPDIR_TEST/state"
mkdir -p "$STATE_DIR"
date +%s > "$STATE_DIR/loop_start"

# --- Test 1: Round 1 returns exit 0 (continue) ---

echo "Test 1: Round 1 with major issues → exit 0 (continue)"

set +e
output1=$(cd "$MOCK_PROJ" && bash .claude/skills/spec-critique-revise-loop/scripts/round.sh \
  --round 1 --max-rounds 3 \
  --exit-criteria "no_major_issues_found" \
  --state-dir "$STATE_DIR" 2>&1)
exit1=$?
set -e

assert_eq "round 1 exit code" "0" "$exit1"
assert_matches "step A header" "Step A \(round 1 of 3, elapsed [0-9]+:[0-9]{2}\): Start round" "$output1"
assert_matches "step B critique" "Step B \(round 1 of 3, elapsed [0-9]+:[0-9]{2}\): Running critics" "$output1"
assert_contains "step D check" "CONTINUE" "$output1"
assert_matches "step E revise with version" "Step E \(round 1 of 3, elapsed [0-9]+:[0-9]{2}\): Running /spec:revise for v[0-9]+" "$output1"
assert_matches "step F summary" "Step F \(round 1 of 3, elapsed [0-9]+:[0-9]{2}\): Round summary" "$output1"
assert_contains "round complete" "ROUND 1 of 3 COMPLETE" "$output1"

# --- Test 2: State persisted ---

echo ""
echo "Test 2: State persisted after round 1"

assert_file_exists "cumulative file" "$STATE_DIR/cumulative"
assert_file_exists "prev_issues file" "$STATE_DIR/prev_issues"
assert_file_exists "critique_files list" "$STATE_DIR/critique_files"
assert_file_exists "ack_files list" "$STATE_DIR/ack_files"

# Check cumulative counts (2 issues, 2 applied)
cumulative=$(cat "$STATE_DIR/cumulative")
assert_contains "cumulative has 2 issues" "2 2 0 0" "$cumulative"

# --- Test 3: Round 2 returns exit 1 (converged) ---

echo ""
echo "Test 3: Round 2 with all-minor issues → exit 1 (converged)"

set +e
output2=$(cd "$MOCK_PROJ" && bash .claude/skills/spec-critique-revise-loop/scripts/round.sh \
  --round 2 --max-rounds 3 \
  --exit-criteria "no_major_issues_found" \
  --state-dir "$STATE_DIR" 2>&1)
exit2=$?
set -e

assert_eq "round 2 exit code" "1" "$exit2"
assert_contains "converged message" "CONVERGED" "$output2"

# Round 2 MUST run revise to write acknowledgements, even though it converged
assert_matches "round 2 still runs revise for acknowledgements" \
  "Step E \(round 2 of 3, elapsed [0-9]+:[0-9]{2}\): Running /spec:revise" "$output2"

# Verify acknowledgement file was written for the converged critique
ack_file2=$(ls "$MOCK_PROJ/specification-critiques/"*-test-acknowledgement.md 2>/dev/null | sort | tail -1 || true)
if [ -n "$ack_file2" ] && [ "$(ls "$MOCK_PROJ/specification-critiques/"*-test-acknowledgement.md 2>/dev/null | wc -l | tr -d ' ')" -eq 2 ]; then
  echo "  PASS: acknowledgement written for converged round (2 total)"
  pass=$((pass + 1))
else
  ack_total=$(ls "$MOCK_PROJ/specification-critiques/"*-test-acknowledgement.md 2>/dev/null | wc -l | tr -d ' ')
  echo "  FAIL: expected 2 acknowledgement files (one per round), got $ack_total"
  fail=$((fail + 1))
fi

# --- Test 4: Report generation ---

echo ""
echo "Test 4: Report generation from state dir"

set +e
report_output=$(bash "$MOCK_PROJ/.claude/skills/spec-critique-revise-loop/scripts/report.sh" \
  --state-dir "$STATE_DIR" \
  --rounds-completed 2 \
  --exit-reason "converged" \
  --exit-criteria "no_major_issues_found" 2>&1)
report_exit=$?
set -e

assert_eq "report exit code" "0" "$report_exit"
assert_contains "final report header" "FINAL REPORT" "$report_output"
assert_contains "rounds completed" "Rounds completed:  2" "$report_output"
assert_contains "exit reason" "Exit reason:       converged" "$report_output"
assert_contains "exit criteria" "Exit criteria:     no_major_issues_found" "$report_output"

# --- Test 5: Critique files listed in report ---

echo ""
echo "Test 5: Files listed in report"

assert_contains "critique file in report" "specification-critiques/" "$report_output"

# --- Summary ---

echo ""
echo "=== round.sh: $pass passed, $fail failed ==="
[ "$fail" -eq 0 ]
