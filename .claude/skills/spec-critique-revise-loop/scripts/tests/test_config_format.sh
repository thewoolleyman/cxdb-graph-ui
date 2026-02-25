#!/usr/bin/env bash
set -euo pipefail

# Tests for the critic-commands.conf config format.
#
# Validates:
#   1. Config file exists and is parseable
#   2. Each non-comment line starts with skill:<model> or bash
#   3. Variable substitution placeholders are present
#   4. Comments and blank lines are skipped correctly
#   5. Edge cases: mixed formats, extra whitespace

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REAL_CONFIG="$SKILL_DIR/config/critic-commands.conf"

TMPDIR_TEST=$(mktemp -d)
trap 'rm -rf "$TMPDIR_TEST"' EXIT

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

# --- Config parser function (mirrors what SKILL.md does) ---
# Parses config file and outputs: TYPE MODEL COMMAND
# For skill:<model> lines: "skill <model> <rest>"
# For bash lines: "bash - <rest>"
parse_config() {
  local config_file="$1"
  while IFS= read -r line; do
    # Skip comments and blank lines
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    [[ -z "${line// /}" ]] && continue

    if [[ "$line" =~ ^skill:([a-z]+)[[:space:]]+(.*) ]]; then
      echo "skill ${BASH_REMATCH[1]} ${BASH_REMATCH[2]}"
    elif [[ "$line" =~ ^bash[[:space:]]+(.*) ]]; then
      echo "bash - ${BASH_REMATCH[1]}"
    else
      echo "UNKNOWN - $line"
    fi
  done < "$config_file"
}

echo "=== test_config_format.sh ==="
echo ""

# --- Test 1: Real config file exists ---

echo "Test 1: Real config file exists and is parseable"

if [ -f "$REAL_CONFIG" ]; then
  echo "  PASS: config file exists"
  pass=$((pass + 1))
else
  echo "  FAIL: config file not found: $REAL_CONFIG"
  fail=$((fail + 1))
fi

# Parse real config
parsed=$(parse_config "$REAL_CONFIG")
line_count=$(echo "$parsed" | wc -l | tr -d ' ')
assert_eq "real config has 2 critic lines" "2" "$line_count"

# --- Test 2: First line is skill:opus ---

echo ""
echo "Test 2: First critic is skill:opus"

first_line=$(echo "$parsed" | head -1)
assert_contains "first line type is skill" "skill opus" "$first_line"
assert_contains "first line has CRITIQUE_PROMPT placeholder" "{CRITIQUE_PROMPT}" "$first_line"

# --- Test 3: Second line is bash ---

echo ""
echo "Test 3: Second critic is bash (opencode)"

second_line=$(echo "$parsed" | tail -1)
assert_contains "second line type is bash" "bash -" "$second_line"
assert_contains "second line has opencode" "opencode" "$second_line"

# --- Test 4: Comments and blank lines are skipped ---

echo ""
echo "Test 4: Comments and blank lines skipped"

cat > "$TMPDIR_TEST/test_config.conf" <<'EOF'
# This is a comment
   # Indented comment

skill:sonnet /spec:critique

# Another comment
bash echo hello
EOF

parsed4=$(parse_config "$TMPDIR_TEST/test_config.conf")
count4=$(echo "$parsed4" | wc -l | tr -d ' ')
assert_eq "skips comments and blanks" "2" "$count4"
assert_contains "first parsed line" "skill sonnet /spec:critique" "$parsed4"
assert_contains "second parsed line" "bash - echo hello" "$parsed4"

# --- Test 5: Various model names ---

echo ""
echo "Test 5: Various model names"

cat > "$TMPDIR_TEST/models_config.conf" <<'EOF'
skill:opus /spec:critique
skill:sonnet /spec:critique --extra
skill:haiku /spec:critique
EOF

parsed5=$(parse_config "$TMPDIR_TEST/models_config.conf")
assert_contains "opus model" "skill opus" "$parsed5"
assert_contains "sonnet model" "skill sonnet" "$parsed5"
assert_contains "haiku model" "skill haiku" "$parsed5"

# --- Test 6: Variable substitution in CRITIQUE_PROMPT ---

echo ""
echo "Test 6: Variable substitution"

cat > "$TMPDIR_TEST/subst_config.conf" <<'EOF'
skill:opus {CRITIQUE_PROMPT}
bash some-tool "{CRITIQUE_PROMPT}"
EOF

parsed6=$(parse_config "$TMPDIR_TEST/subst_config.conf")
first6=$(echo "$parsed6" | head -1)
second6=$(echo "$parsed6" | tail -1)
assert_contains "skill line has placeholder" "{CRITIQUE_PROMPT}" "$first6"
assert_contains "bash line has placeholder" "{CRITIQUE_PROMPT}" "$second6"

# --- Test 7: Unknown format line ---

echo ""
echo "Test 7: Unknown format detected"

cat > "$TMPDIR_TEST/bad_config.conf" <<'EOF'
skill:opus /spec:critique
this is not a valid line
bash echo hello
EOF

parsed7=$(parse_config "$TMPDIR_TEST/bad_config.conf")
assert_contains "unknown line flagged" "UNKNOWN" "$parsed7"

# --- Test 8: No CRITIQUE_TOOLS variable needed (removed from new format) ---

echo ""
echo "Test 8: Config does not reference CRITIQUE_TOOLS"

if grep -q '{CRITIQUE_TOOLS}' "$REAL_CONFIG"; then
  echo "  FAIL: real config still references {CRITIQUE_TOOLS} (removed in new format)"
  fail=$((fail + 1))
else
  echo "  PASS: no CRITIQUE_TOOLS reference"
  pass=$((pass + 1))
fi

# --- Summary ---

echo ""
echo "=== config_format: $pass passed, $fail failed ==="
[ "$fail" -eq 0 ]
