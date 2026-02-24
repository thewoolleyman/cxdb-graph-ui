#!/usr/bin/env bash
# Run all minitest specs for the kilroy-generate-pipeline skill.
# Usage: bash tests/run_tests.sh
# Exit code: 0 if all pass, 1 if any fail.

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "$0")" && pwd)"
failures=0
total=0

for test_file in "$TESTS_DIR"/test_*.rb; do
  total=$((total + 1))
  echo "=== $(basename "$test_file") ==="
  if ruby "$test_file"; then
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
