#!/usr/bin/env bash
# Run all bash test suites for the spec-critique-revise-loop skill.
# Usage: bash tests/run_tests.sh
# Exit code: 0 if all pass, 1 if any fail.

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "$0")" && pwd)"
failures=0
total=0

for test_file in "$TESTS_DIR"/test_*.sh; do
  total=$((total + 1))
  name="$(basename "$test_file" .sh)"
  echo "=== $name ==="
  if bash "$test_file"; then
    echo ""
  else
    failures=$((failures + 1))
    echo ""
  fi
done

echo "==============================="
echo "Ran $total test files, $failures failed."
echo "==============================="

if [ "$failures" -gt 0 ]; then
  exit 1
fi
