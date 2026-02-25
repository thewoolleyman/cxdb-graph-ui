#!/usr/bin/env bash
set -euo pipefail

# Tests for type-aware {CRITIQUE_PROMPT} substitution in round.sh.
#
# Tests:
#   1. bash critic with critique_prompt → ". Additional instructions: ..."
#   2. non-bash critic with critique_prompt → "/spec:critique ..."
#   3. bash critic without critique_prompt → empty (no /spec:critique prefix)
#   4. non-bash critic without critique_prompt → "/spec:critique" only
#   5. Both critic types in the same config get different expansions

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

# --- Test helpers ---

pass=0
fail=0

assert_contains() {
  local test_name="$1" expected="$2" actual="$3"
  if echo "$actual" | grep -qF "$expected"; then
    echo "  PASS: $test_name"
    pass=$((pass + 1))
  else
    echo "  FAIL: $test_name"
    echo "    expected to contain: '$expected'"
    echo "    actual (last 5 lines): $(echo "$actual" | tail -5)"
    fail=$((fail + 1))
  fi
}

assert_not_contains() {
  local test_name="$1" unexpected="$2" actual="$3"
  if ! echo "$actual" | grep -qF "$unexpected"; then
    echo "  PASS: $test_name"
    pass=$((pass + 1))
  else
    echo "  FAIL: $test_name"
    echo "    expected NOT to contain: '$unexpected'"
    fail=$((fail + 1))
  fi
}

# Create a mock critic script that:
#   - Records all received args to CAPTURE_FILE (hardcoded at creation time)
#   - Creates a minor-only critique file (so round converges without calling revise)
#   - Critique name is determined by CRITIQUE_NAME (hardcoded at creation time)
_make_critic() {
  local script_path="$1" capture_file="$2" critique_name="$3"
  cat > "$script_path" <<EOF
#!/usr/bin/env bash
CRITIQUES_DIR="specification/critiques"
mkdir -p "\$CRITIQUES_DIR"
# Record received args to capture file
echo "\$*" >> "$capture_file"
# Create minor-only critique
max_v=0
for f in "\$CRITIQUES_DIR"/*.md; do
  [ -f "\$f" ] || continue
  v=\$(basename "\$f" | grep -oE '^v[0-9]+' | sed 's/^v//')
  [ -n "\$v" ] && [ "\$v" -gt "\$max_v" ] && max_v=\$v
done
next_v=\$((max_v + 1))
cat > "\$CRITIQUES_DIR/v\${next_v}-${critique_name}.md" <<CRITIQUE
# Critique v\${next_v} (${critique_name})

## Issue #1: Minor trivial cosmetic nitpick

### The problem

A minor cosmetic issue only.

### Suggestion

Optional improvement.
CRITIQUE
EOF
  chmod +x "$script_path"
}

_run_round() {
  local proj="$1" state_dir="$2"
  shift 2
  set +e
  output=$(cd "$proj" && bash .claude/skills/spec-critique-revise-loop/scripts/round.sh \
    --round 1 --max-rounds 3 \
    --exit-criteria "no_major_issues_found" \
    --state-dir "$state_dir" \
    "$@" 2>&1)
  set -e
  echo "$output"
}

echo "=== test_critique_prompt_substitution.sh ==="
echo ""

# --- Test 1: bash critic → ". Additional instructions: ..." ---

echo "Test 1: bash critic gets '. Additional instructions:' expansion"

CAPTURE1="$TMPDIR_TEST/capture1.txt"
SCRIPT1="$TMPDIR_TEST/critic1.sh"
_make_critic "$SCRIPT1" "$CAPTURE1" "bash1"

cat > "$MOCK_PROJ/.claude/skills/spec-critique-revise-loop/config/critic-commands.conf" <<EOF
bash $SCRIPT1 {CRITIQUE_PROMPT}
EOF

STATE1="$TMPDIR_TEST/state1"; mkdir -p "$STATE1"
output1=$(_run_round "$MOCK_PROJ" "$STATE1" --critique-prompt "FOCUS_ON_BLOCKING")

if [ -f "$CAPTURE1" ]; then
  captured1=$(cat "$CAPTURE1")
  assert_contains "bash critic receives '. Additional instructions: FOCUS_ON_BLOCKING'" \
    ". Additional instructions: FOCUS_ON_BLOCKING" "$captured1"
  assert_not_contains "bash critic does NOT receive /spec:critique prefix" \
    "/spec:critique" "$captured1"
else
  echo "  FAIL: capture file not written by bash critic (round output: $(echo "$output1" | tail -3))"
  fail=$((fail + 2))
fi

# --- Test 2: non-bash critic → "/spec:critique ..." ---

echo ""
echo "Test 2: non-bash critic gets '/spec:critique ...' expansion"

CAPTURE2="$TMPDIR_TEST/capture2.txt"
SCRIPT2="$TMPDIR_TEST/critic2.sh"
_make_critic "$SCRIPT2" "$CAPTURE2" "raw2"
rm -f "$MOCK_PROJ/specification/critiques/"*.md 2>/dev/null || true

cat > "$MOCK_PROJ/.claude/skills/spec-critique-revise-loop/config/critic-commands.conf" <<EOF
$SCRIPT2 {CRITIQUE_PROMPT}
EOF

STATE2="$TMPDIR_TEST/state2"; mkdir -p "$STATE2"
output2=$(_run_round "$MOCK_PROJ" "$STATE2" --critique-prompt "FOCUS_ON_BLOCKING")

if [ -f "$CAPTURE2" ]; then
  captured2=$(cat "$CAPTURE2")
  assert_contains "non-bash critic receives '/spec:critique FOCUS_ON_BLOCKING'" \
    "/spec:critique FOCUS_ON_BLOCKING" "$captured2"
  assert_not_contains "non-bash critic does NOT receive '. Additional instructions:'" \
    ". Additional instructions:" "$captured2"
else
  echo "  FAIL: capture file not written by non-bash critic"
  fail=$((fail + 2))
fi

# --- Test 3: bash critic, no critique_prompt → empty expansion ---

echo ""
echo "Test 3: bash critic with no --critique-prompt gets empty expansion"

CAPTURE3="$TMPDIR_TEST/capture3.txt"
SCRIPT3="$TMPDIR_TEST/critic3.sh"
_make_critic "$SCRIPT3" "$CAPTURE3" "bash3"
rm -f "$MOCK_PROJ/specification/critiques/"*.md 2>/dev/null || true

cat > "$MOCK_PROJ/.claude/skills/spec-critique-revise-loop/config/critic-commands.conf" <<EOF
bash $SCRIPT3 {CRITIQUE_PROMPT}
EOF

STATE3="$TMPDIR_TEST/state3"; mkdir -p "$STATE3"
output3=$(_run_round "$MOCK_PROJ" "$STATE3")

if [ -f "$CAPTURE3" ]; then
  captured3=$(cat "$CAPTURE3")
  assert_not_contains "bash critic (no prompt) receives no /spec:critique" \
    "/spec:critique" "$captured3"
  assert_not_contains "bash critic (no prompt) receives no 'Additional instructions:'" \
    "Additional instructions:" "$captured3"
else
  echo "  FAIL: capture file not written"
  fail=$((fail + 2))
fi

# --- Test 4: non-bash critic, no critique_prompt → "/spec:critique" only ---

echo ""
echo "Test 4: non-bash critic with no --critique-prompt gets '/spec:critique' only"

CAPTURE4="$TMPDIR_TEST/capture4.txt"
SCRIPT4="$TMPDIR_TEST/critic4.sh"
_make_critic "$SCRIPT4" "$CAPTURE4" "raw4"
rm -f "$MOCK_PROJ/specification/critiques/"*.md 2>/dev/null || true

cat > "$MOCK_PROJ/.claude/skills/spec-critique-revise-loop/config/critic-commands.conf" <<EOF
$SCRIPT4 {CRITIQUE_PROMPT}
EOF

STATE4="$TMPDIR_TEST/state4"; mkdir -p "$STATE4"
output4=$(_run_round "$MOCK_PROJ" "$STATE4")

if [ -f "$CAPTURE4" ]; then
  captured4=$(cat "$CAPTURE4")
  assert_contains "non-bash critic (no prompt) receives '/spec:critique'" \
    "/spec:critique" "$captured4"
  assert_not_contains "non-bash critic (no prompt) has no 'Additional instructions:'" \
    "Additional instructions:" "$captured4"
else
  echo "  FAIL: capture file not written"
  fail=$((fail + 2))
fi

# --- Test 5: bash and non-bash critics in same config get different expansions ---

echo ""
echo "Test 5: bash and non-bash critics in same round get different expansions"

CAPTURE5_BASH="$TMPDIR_TEST/capture5_bash.txt"
CAPTURE5_RAW="$TMPDIR_TEST/capture5_raw.txt"
SCRIPT5_BASH="$TMPDIR_TEST/critic5_bash.sh"
SCRIPT5_RAW="$TMPDIR_TEST/critic5_raw.sh"
_make_critic "$SCRIPT5_BASH" "$CAPTURE5_BASH" "bash5"
_make_critic "$SCRIPT5_RAW" "$CAPTURE5_RAW" "raw5"
rm -f "$MOCK_PROJ/specification/critiques/"*.md 2>/dev/null || true

cat > "$MOCK_PROJ/.claude/skills/spec-critique-revise-loop/config/critic-commands.conf" <<EOF
bash $SCRIPT5_BASH {CRITIQUE_PROMPT}
$SCRIPT5_RAW {CRITIQUE_PROMPT}
EOF

STATE5="$TMPDIR_TEST/state5"; mkdir -p "$STATE5"
output5=$(_run_round "$MOCK_PROJ" "$STATE5" --critique-prompt "MVP_ONLY")

if [ -f "$CAPTURE5_BASH" ]; then
  captured5_bash=$(cat "$CAPTURE5_BASH")
  assert_contains "bash critic gets '. Additional instructions: MVP_ONLY'" \
    ". Additional instructions: MVP_ONLY" "$captured5_bash"
  assert_not_contains "bash critic does NOT get /spec:critique" \
    "/spec:critique" "$captured5_bash"
else
  echo "  FAIL: bash capture file not written"
  fail=$((fail + 2))
fi

if [ -f "$CAPTURE5_RAW" ]; then
  captured5_raw=$(cat "$CAPTURE5_RAW")
  assert_contains "non-bash critic gets '/spec:critique MVP_ONLY'" \
    "/spec:critique MVP_ONLY" "$captured5_raw"
  assert_not_contains "non-bash critic does NOT get '. Additional instructions:'" \
    ". Additional instructions:" "$captured5_raw"
else
  echo "  FAIL: raw capture file not written"
  fail=$((fail + 2))
fi

# --- Summary ---

echo ""
echo "=== critique_prompt_substitution: $pass passed, $fail failed ==="
[ "$fail" -eq 0 ]
