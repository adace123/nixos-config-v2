#!/usr/bin/env bash
# Verify that the literal nixConfig block in flake.nix stays in sync with
# nix-caches.nix (the single source of truth). flake.nix must duplicate the
# lists because nix reads nixConfig without evaluating imports — this script
# catches drift when a cache is added or removed.
#
# The repo root comes from git, not from `${BASH_SOURCE[0]}`: this script runs
# from the nix store under pre-commit, so its own path says nothing about where
# the repository is. (It used to derive the root that way, which made it look for
# `/nix/flake.nix`, fail every awk, and report OK for two empty lists — a guard
# that passed for years without reading a single line.)
set -euo pipefail

root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

for file in nix-caches.nix flake.nix; do
	if [ ! -f "$root/$file" ]; then
		echo "ERROR: $root/$file does not exist — run this from inside the repo"
		exit 1
	fi
done

extract() {
	local file="$1" name="$2"
	# `-v name="$name"`, not the `''${name}` this used to carry: those two quote
	# characters are Nix escaping that leaked into a shell script, and they made
	# the pattern `''extra-substituters[[:space:]]*=` match nothing at all.
	awk -v name="$name" '
        $0 ~ name"[[:space:]]*=[[:space:]]*\\[" { found = 1; next }
        found && /\];/ { found = 0 }
        found
    ' "$file" | grep -o '"[^"]*"' | tr -d '"' | sort
}

status=0
for list in extra-substituters extra-trusted-public-keys; do
	keys="$(extract "$root/nix-caches.nix" "$list")"
	if [ -z "$keys" ]; then
		echo "ERROR: no '$list' found in nix-caches.nix — the extractor is broken"
		status=1
		continue
	fi
	if ! diff <(printf '%s\n' "$keys") \
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
