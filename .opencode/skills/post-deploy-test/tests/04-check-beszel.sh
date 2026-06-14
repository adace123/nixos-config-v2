#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=test-lib.sh disable=SC1091
source "$SCRIPT_DIR/test-lib.sh"

HOST="coruscant.local"

echo "--- Test: Beszel hub service is active ($HOST) ---"

STATUS=$(ssh "root@$HOST" "systemctl is-active beszel-hub 2>&1") || {
	die "Beszel hub is not active (status: $STATUS)"
}

if [ "$STATUS" != "active" ]; then
	die "Expected beszel-hub to be active, got: $STATUS"
fi

pass "Beszel hub service is active"

echo "--- Test: Beszel hub is listening on port 8090 ($HOST) ---"

LISTENING=$(ssh "root@$HOST" "ss -tlnp | grep -q ':8090' && echo yes || echo no") || die "Cannot check port 8090"

if [ "$LISTENING" != "yes" ]; then
	die "Beszel hub is not listening on port 8090"
fi

pass "Beszel hub is listening on port 8090"
