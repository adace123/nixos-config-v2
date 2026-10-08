#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=test-lib.sh disable=SC1091
source "$SCRIPT_DIR/test-lib.sh"

HOST="coruscant.local"
ERROR_PATTERNS="ERROR|FATAL|CRITICAL|unable to open database|corrupt|failed to initialize recorder|recovery mode|Activating recovery"

echo "--- Test: Home Assistant logs are error-free ($HOST) ---"

LOGS=$(ssh "root@$HOST" "podman logs home-assistant 2>&1 | tail -200") || {
	die "Cannot fetch HA container logs from $HOST"
}

ERRORS=$(echo "$LOGS" | grep -iE "$ERROR_PATTERNS" | head -10 || true)

if [ -n "$ERRORS" ]; then
	echo "$ERRORS"
	die "Found error patterns in HA logs"
fi

pass "HA logs on $HOST are error-free"
