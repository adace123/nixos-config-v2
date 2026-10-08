#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=test-lib.sh disable=SC1091
source "$SCRIPT_DIR/test-lib.sh"

HOST="coruscant.local"

echo "--- Test: Home Assistant container is running ($HOST) ---"

STATUS=$(ssh "root@$HOST" "podman ps --filter name=home-assistant --format '{{.Status}}' 2>&1") || {
	die "Cannot check HA container status"
}

if ! echo "$STATUS" | grep -q "^Up"; then
	die "HA container is not running (status: $STATUS)"
fi

echo "  Container status: $STATUS"
pass "HA container is running and healthy"
