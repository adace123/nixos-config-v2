#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)

echo "=== Post-Deploy Test Suite ==="
echo "Host: coruscant.local"
echo "Started: $(date -u)"
echo ""

FAILURES=0

for test_script in "$SCRIPT_DIR"/[0-9][0-9]-*.sh; do
	name=$(basename "$test_script" .sh)
	echo "--- $name ---"
	if bash "$test_script"; then
		echo ""
	else
		FAILURES=$((FAILURES + 1))
	fi
done

echo "=== Results: $FAILURES failures ==="
if [ "$FAILURES" -gt 0 ]; then
	echo "FAIL"
	exit 1
fi
echo "PASS"
