#!/usr/bin/env bash
set -euo pipefail

# Integration test for multi-critic support in round.sh.
#
# Tests:
#   1. Two critics run in parallel, both produce critique files
#   2. All-must-converge: one converged + one not → continue
#   3. All converged → exit 1
#   4. One critic fails → continues with the successful one
#   5. Parallel execution (PIDs differ)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

TMPDIR_TEST=$(mktemp -d)
trap 'rm -rf "$TMPDIR_TEST"' EXIT

# --- Set up mock project ---

MOCK_PROJ="$TMPDIR_TEST/project"
mkdir -p "$MOCK_PROJ/.claude/skills/spec-critique-revise-loop/scripts"
mkdir -p "$MOCK_PROJ/.claude/skills/spec-critique-revise-loop/config"
mkdir -p "$MOCK_PROJ/specification/critiques"

cp "$SCRIPT_DIR/round.sh" "$MOCK_PROJ/.claude/skills/spec-critique-revise-loop/scripts/"
cp "$SCRIPT_DIR/check_exit.sh" "$MOCK_PROJ/.claude/skills/spec-critique-revise-loop/scripts/"
cp "$SCRIPT_DIR/round_summary.sh" "$MOCK_PROJ/.claude/skills/spec-critique-revise-loop/scripts/"
cp "$SCRIPT_DIR/elapsed_time.sh" "$MOCK_PROJ/.claude/skills/spec-critique-revise-loop/scripts/"
cp "$SCRIPT_DIR/report.sh" "$MOCK_PROJ/.claude/skills/spec-critique-revise-loop/scripts/"
chmod +x "$MOCK_PROJ/.claude/skills/spec-critique-revise-loop/scripts/"*.sh

# --- Create two mock critic commands ---

# Mock critic A: creates v{N}-alpha.md with major issues on round 1, minor on round 2
MOCK_CRITIC_A="$TMPDIR_TEST/mock_critic_a"
cat > "$MOCK_CRITIC_A" <<'SCRIPT'
#!/usr/bin/env bash
CRITIQUES_DIR="specification/critiques"
COUNTER_FILE="${MOCK_COUNTER_A:-/tmp/mock_counter_a}"

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

# Record PID for parallel verification
echo "$$" >> "${MOCK_PID_FILE:-/tmp/mock_pids}"

if [ "$round" -eq 1 ]; then
  cat > "$CRITIQUES_DIR/v${next_v}-alpha.md" <<EOF
# Critique v${next_v} (alpha)
## Issue #1: Major problem from alpha
### The problem
A serious issue.
### Suggestion
Fix it.
EOF
  echo "Alpha critic: 1 major issue (round $round)"
else
  cat > "$CRITIQUES_DIR/v${next_v}-alpha.md" <<EOF
# Critique v${next_v} (alpha)
## Issue #1: Minor cosmetic nitpick from alpha
### The problem
A trivial minor cosmetic issue.
### Suggestion
Optional fix.
EOF
  echo "Alpha critic: 1 minor issue (round $round)"
fi
SCRIPT
chmod +x "$MOCK_CRITIC_A"

# Mock critic B: creates v{N}-beta.md with major issues on round 1, minor on round 2
MOCK_CRITIC_B="$TMPDIR_TEST/mock_critic_b"
cat > "$MOCK_CRITIC_B" <<'SCRIPT'
#!/usr/bin/env bash
CRITIQUES_DIR="specification/critiques"
COUNTER_FILE="${MOCK_COUNTER_B:-/tmp/mock_counter_b}"

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

# Record PID for parallel verification
echo "$$" >> "${MOCK_PID_FILE:-/tmp/mock_pids}"

if [ "$round" -eq 1 ]; then
  cat > "$CRITIQUES_DIR/v${next_v}-beta.md" <<EOF
# Critique v${next_v} (beta)
## Issue #1: Major problem from beta
### The problem
A different serious issue.
### Suggestion
Fix it differently.
EOF
  echo "Beta critic: 1 major issue (round $round)"
else
  cat > "$CRITIQUES_DIR/v${next_v}-beta.md" <<EOF
# Critique v${next_v} (beta)
## Issue #1: Minor trivial nitpick from beta
### The problem
A trivial cosmetic issue.
### Suggestion
Optional.
EOF
  echo "Beta critic: 1 minor issue (round $round)"
fi
SCRIPT
chmod +x "$MOCK_CRITIC_B"

# Mock revise command (creates acknowledgement for all unacknowledged critiques)
MOCK_CLAUDE="$TMPDIR_TEST/claude"
cat > "$MOCK_CLAUDE" <<'SCRIPT'
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

CRITIQUES_DIR="specification/critiques"

if [[ "$prompt" == /spec:revise* ]]; then
  for f in "$CRITIQUES_DIR"/v*-*.md; do
    [ -f "$f" ] || continue
    [[ "$f" == *acknowledgement* ]] && continue
    base=$(basename "$f" .md)
    ack="$CRITIQUES_DIR/${base}-acknowledgement.md"
    [ -f "$ack" ] && continue
    v=$(echo "$base" | grep -oE '^v[0-9]+')
    {
      echo "# Acknowledgement ${v} (${base})"
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
SCRIPT
chmod +x "$MOCK_CLAUDE"

# --- Test helpers ---

export PATH="$TMPDIR_TEST:$PATH"
export MOCK_COUNTER_A="$TMPDIR_TEST/counter_a"
export MOCK_COUNTER_B="$TMPDIR_TEST/counter_b"
MOCK_PID_FILE="$TMPDIR_TEST/pids"
export MOCK_PID_FILE

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

echo "=== test_multi_critic.sh ==="
echo ""

# --- Test 1: Two critics produce files in parallel ---

echo "Test 1: Two critics run in parallel, both produce critique files"

# Write config with both mock critics
cat > "$MOCK_PROJ/.claude/skills/spec-critique-revise-loop/config/critic-commands.conf" <<EOF
# Two mock critics
$MOCK_CRITIC_A
$MOCK_CRITIC_B
EOF

STATE_DIR="$TMPDIR_TEST/state1"
mkdir -p "$STATE_DIR"

set +e
output1=$(cd "$MOCK_PROJ" && bash .claude/skills/spec-critique-revise-loop/scripts/round.sh \
  --round 1 --max-rounds 3 \
  --exit-criteria "no_major_issues_found" \
  --state-dir "$STATE_DIR" 2>&1)
exit1=$?
set -e

assert_eq "round 1 exit code (continue)" "0" "$exit1"
assert_contains "alpha critic output" "Alpha critic" "$output1"
assert_contains "beta critic output" "Beta critic" "$output1"
assert_contains "2 critique files found" "New critique files (2)" "$output1"
# Check that both alpha and beta critique files exist (version may vary due to race)
alpha_count=$(ls "$MOCK_PROJ/specification/critiques/"*-alpha.md 2>/dev/null | wc -l | tr -d ' ')
beta_count=$(ls "$MOCK_PROJ/specification/critiques/"*-beta.md 2>/dev/null | wc -l | tr -d ' ')
if [ "$alpha_count" -ge 1 ]; then
  echo "  PASS: alpha critique file exists"
  pass=$((pass + 1))
else
  echo "  FAIL: no alpha critique file found"
  fail=$((fail + 1))
fi
if [ "$beta_count" -ge 1 ]; then
  echo "  PASS: beta critique file exists"
  pass=$((pass + 1))
else
  echo "  FAIL: no beta critique file found"
  fail=$((fail + 1))
fi

# --- Test 2: Parallel execution verification ---

echo ""
echo "Test 2: Critics ran as separate processes"

if [ -f "$MOCK_PID_FILE" ]; then
  pid_count=$(sort -u "$MOCK_PID_FILE" | wc -l | tr -d ' ')
  if [ "$pid_count" -ge 2 ]; then
    echo "  PASS: $pid_count distinct PIDs recorded"
    pass=$((pass + 1))
  else
    echo "  FAIL: expected at least 2 distinct PIDs, got $pid_count"
    fail=$((fail + 1))
  fi
else
  echo "  FAIL: PID file not found"
  fail=$((fail + 1))
fi

# --- Test 3: All-must-converge (round 2, both minor → converged) ---

echo ""
echo "Test 3: All critics converge → exit 1"

STATE_DIR2="$TMPDIR_TEST/state2"
cp -r "$STATE_DIR" "$STATE_DIR2"

set +e
output2=$(cd "$MOCK_PROJ" && bash .claude/skills/spec-critique-revise-loop/scripts/round.sh \
  --round 2 --max-rounds 3 \
  --exit-criteria "no_major_issues_found" \
  --state-dir "$STATE_DIR2" 2>&1)
exit2=$?
set -e

assert_eq "round 2 exit code (converged)" "1" "$exit2"
assert_contains "all converged message" "ALL critics converged" "$output2"

# --- Test 4: Mixed convergence (one major, one minor → continue) ---

echo ""
echo "Test 4: One critic has major issues, one converged → continue"

# Create a config where critic A has major issues and critic B has minor
MOCK_CRITIC_MAJOR="$TMPDIR_TEST/mock_critic_major"
cat > "$MOCK_CRITIC_MAJOR" <<'SCRIPT'
#!/usr/bin/env bash
CRITIQUES_DIR="specification/critiques"
max_v=0
for f in "$CRITIQUES_DIR"/*.md; do
  [ -f "$f" ] || continue
  v=$(basename "$f" | grep -oE '^v[0-9]+' | sed 's/^v//')
  [ -n "$v" ] && [ "$v" -gt "$max_v" ] && max_v=$v
done
next_v=$((max_v + 1))
cat > "$CRITIQUES_DIR/v${next_v}-major.md" <<EOF
# Critique v${next_v} (major)
## Issue #1: Serious architecture flaw
### The problem
Big problem.
### Suggestion
Redesign.
EOF
echo "Major critic done."
SCRIPT
chmod +x "$MOCK_CRITIC_MAJOR"

MOCK_CRITIC_MINOR="$TMPDIR_TEST/mock_critic_minor"
cat > "$MOCK_CRITIC_MINOR" <<'SCRIPT'
#!/usr/bin/env bash
CRITIQUES_DIR="specification/critiques"
max_v=0
for f in "$CRITIQUES_DIR"/*.md; do
  [ -f "$f" ] || continue
  v=$(basename "$f" | grep -oE '^v[0-9]+' | sed 's/^v//')
  [ -n "$v" ] && [ "$v" -gt "$max_v" ] && max_v=$v
done
next_v=$((max_v + 1))
cat > "$CRITIQUES_DIR/v${next_v}-minor.md" <<EOF
# Critique v${next_v} (minor)
## Issue #1: Cosmetic trivial nitpick
### The problem
A minor trivial cosmetic issue.
### Suggestion
Optional.
EOF
echo "Minor critic done."
SCRIPT
chmod +x "$MOCK_CRITIC_MINOR"

# Set up fresh project for this test
MOCK_PROJ2="$TMPDIR_TEST/project2"
mkdir -p "$MOCK_PROJ2/.claude/skills/spec-critique-revise-loop/scripts"
mkdir -p "$MOCK_PROJ2/.claude/skills/spec-critique-revise-loop/config"
mkdir -p "$MOCK_PROJ2/specification/critiques"
cp "$SCRIPT_DIR/round.sh" "$MOCK_PROJ2/.claude/skills/spec-critique-revise-loop/scripts/"
cp "$SCRIPT_DIR/check_exit.sh" "$MOCK_PROJ2/.claude/skills/spec-critique-revise-loop/scripts/"
cp "$SCRIPT_DIR/round_summary.sh" "$MOCK_PROJ2/.claude/skills/spec-critique-revise-loop/scripts/"
cp "$SCRIPT_DIR/elapsed_time.sh" "$MOCK_PROJ2/.claude/skills/spec-critique-revise-loop/scripts/"
cp "$SCRIPT_DIR/report.sh" "$MOCK_PROJ2/.claude/skills/spec-critique-revise-loop/scripts/"
chmod +x "$MOCK_PROJ2/.claude/skills/spec-critique-revise-loop/scripts/"*.sh

cat > "$MOCK_PROJ2/.claude/skills/spec-critique-revise-loop/config/critic-commands.conf" <<EOF
$MOCK_CRITIC_MAJOR
$MOCK_CRITIC_MINOR
EOF

STATE_DIR3="$TMPDIR_TEST/state3"
mkdir -p "$STATE_DIR3"

set +e
output3=$(cd "$MOCK_PROJ2" && bash .claude/skills/spec-critique-revise-loop/scripts/round.sh \
  --round 1 --max-rounds 3 \
  --exit-criteria "no_major_issues_found" \
  --state-dir "$STATE_DIR3" 2>&1)
exit3=$?
set -e

assert_eq "mixed convergence exit code (continue)" "0" "$exit3"
assert_contains "major issues message" "Major issues found" "$output3"

# --- Test 5: One critic fails → continues with the other ---

echo ""
echo "Test 5: One critic fails, other succeeds → continues"

MOCK_CRITIC_FAIL="$TMPDIR_TEST/mock_critic_fail"
cat > "$MOCK_CRITIC_FAIL" <<'SCRIPT'
#!/usr/bin/env bash
echo "Failing critic" >&2
exit 1
SCRIPT
chmod +x "$MOCK_CRITIC_FAIL"

MOCK_PROJ3="$TMPDIR_TEST/project3"
mkdir -p "$MOCK_PROJ3/.claude/skills/spec-critique-revise-loop/scripts"
mkdir -p "$MOCK_PROJ3/.claude/skills/spec-critique-revise-loop/config"
mkdir -p "$MOCK_PROJ3/specification/critiques"
cp "$SCRIPT_DIR/round.sh" "$MOCK_PROJ3/.claude/skills/spec-critique-revise-loop/scripts/"
cp "$SCRIPT_DIR/check_exit.sh" "$MOCK_PROJ3/.claude/skills/spec-critique-revise-loop/scripts/"
cp "$SCRIPT_DIR/round_summary.sh" "$MOCK_PROJ3/.claude/skills/spec-critique-revise-loop/scripts/"
cp "$SCRIPT_DIR/elapsed_time.sh" "$MOCK_PROJ3/.claude/skills/spec-critique-revise-loop/scripts/"
cp "$SCRIPT_DIR/report.sh" "$MOCK_PROJ3/.claude/skills/spec-critique-revise-loop/scripts/"
chmod +x "$MOCK_PROJ3/.claude/skills/spec-critique-revise-loop/scripts/"*.sh

cat > "$MOCK_PROJ3/.claude/skills/spec-critique-revise-loop/config/critic-commands.conf" <<EOF
$MOCK_CRITIC_FAIL
$MOCK_CRITIC_MAJOR
EOF

STATE_DIR4="$TMPDIR_TEST/state4"
mkdir -p "$STATE_DIR4"

set +e
output4=$(cd "$MOCK_PROJ3" && bash .claude/skills/spec-critique-revise-loop/scripts/round.sh \
  --round 1 --max-rounds 3 \
  --exit-criteria "no_major_issues_found" \
  --state-dir "$STATE_DIR4" 2>&1)
exit4=$?
set -e

assert_eq "partial failure exit code (continue)" "0" "$exit4"
assert_contains "failure warning" "WARNING" "$output4"
assert_contains "continuing message" "continuing with successful" "$output4"

# --- Test 6: All critics fail → exit 10 ---

echo ""
echo "Test 6: All critics fail → error exit"

MOCK_PROJ4="$TMPDIR_TEST/project4"
mkdir -p "$MOCK_PROJ4/.claude/skills/spec-critique-revise-loop/scripts"
mkdir -p "$MOCK_PROJ4/.claude/skills/spec-critique-revise-loop/config"
mkdir -p "$MOCK_PROJ4/specification/critiques"
cp "$SCRIPT_DIR/round.sh" "$MOCK_PROJ4/.claude/skills/spec-critique-revise-loop/scripts/"
cp "$SCRIPT_DIR/check_exit.sh" "$MOCK_PROJ4/.claude/skills/spec-critique-revise-loop/scripts/"
cp "$SCRIPT_DIR/round_summary.sh" "$MOCK_PROJ4/.claude/skills/spec-critique-revise-loop/scripts/"
cp "$SCRIPT_DIR/elapsed_time.sh" "$MOCK_PROJ4/.claude/skills/spec-critique-revise-loop/scripts/"
cp "$SCRIPT_DIR/report.sh" "$MOCK_PROJ4/.claude/skills/spec-critique-revise-loop/scripts/"
chmod +x "$MOCK_PROJ4/.claude/skills/spec-critique-revise-loop/scripts/"*.sh

cat > "$MOCK_PROJ4/.claude/skills/spec-critique-revise-loop/config/critic-commands.conf" <<EOF
$MOCK_CRITIC_FAIL
$MOCK_CRITIC_FAIL
EOF

STATE_DIR5="$TMPDIR_TEST/state5"
mkdir -p "$STATE_DIR5"

set +e
output5=$(cd "$MOCK_PROJ4" && bash .claude/skills/spec-critique-revise-loop/scripts/round.sh \
  --round 1 --max-rounds 3 \
  --exit-criteria "no_major_issues_found" \
  --state-dir "$STATE_DIR5" 2>&1)
exit5=$?
set -e

assert_eq "all-fail exit code (error)" "10" "$exit5"
assert_contains "all failed message" "ALL critics failed" "$output5"

# --- Summary ---

echo ""
echo "=== multi_critic: $pass passed, $fail failed ==="
[ "$fail" -eq 0 ]
