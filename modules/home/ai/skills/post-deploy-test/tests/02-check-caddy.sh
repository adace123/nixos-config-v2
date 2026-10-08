#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=test-lib.sh disable=SC1091
source "$SCRIPT_DIR/test-lib.sh"

HOST="coruscant.local"

echo "--- Test: Caddy service is active ($HOST) ---"

STATUS=$(ssh "root@$HOST" "systemctl is-active caddy 2>&1") || {
	die "Caddy is not active (status: $STATUS)"
}

if [ "$STATUS" != "active" ]; then
	die "Expected caddy to be active, got: $STATUS"
fi

pass "Caddy service is active"

echo "--- Test: Caddy TLS certificate exists ($HOST) ---"

CERT_DIR=$(ssh "root@$HOST" "ls /var/lib/caddy/.local/share/caddy/certificates/acme-v02.api.letsencrypt.org-directory/ 2>&1") || {
	die "Cannot list TLS certificate directory"
}

if [ -z "$CERT_DIR" ]; then
	die "No TLS certificates found"
fi

echo "  Certificate: $CERT_DIR"
pass "Caddy TLS certificate exists"
