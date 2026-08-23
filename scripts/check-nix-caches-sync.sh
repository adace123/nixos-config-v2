#!/usr/bin/env bash
# Verify that the literal nixConfig block in flake.nix stays in sync with
# nix-caches.nix (the single source of truth). flake.nix must duplicate the
# lists because nix reads nixConfig without evaluating imports — this script
# catches drift when a cache is added or removed.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

extract() {
	local file="$1" name="$2"
	awk -v name="''${name}" '
        $0 ~ name"[[:space:]]*=[[:space:]]*\\[" { found = 1; next }
        found && /\];/ { found = 0 }
        found
    ' "$file" | grep -o '"[^"]*"' | tr -d '"' | sort
}

status=0
for list in extra-substituters extra-trusted-public-keys; do
	if ! diff <(extract "$root/nix-caches.nix" "$list") \
		<(extract "$root/flake.nix" "$list") >/dev/null; then
		echo "ERROR: '$list' differs between flake.nix (nixConfig) and nix-caches.nix"
		diff <(extract "$root/nix-caches.nix" "$list") \
			<(extract "$root/flake.nix" "$list") || true
		status=1
	else
		echo "OK: '$list' in sync"
	fi
done

exit "$status"
