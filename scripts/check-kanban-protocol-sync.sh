#!/usr/bin/env bash
# Verify that the board protocol quoted in docs/kanban.md is still exactly what
# the plugin appends to a dispatch prompt.
#
# The block is user-facing documentation *and* a prompt an agent acts on, kept in
# two places by necessity (Python source, Markdown docs). It has drifted before —
# the `found more work?` line went missing — and a doc that promises an agent
# something the prompt never tells it is worse than no doc.
#
# Usage (the pre-commit hook passes the packaged interpreter and app):
#   check-kanban-protocol-sync.sh <python> <appdir>
#
# The repo root comes from git, not from `${BASH_SOURCE[0]}`: under pre-commit
# this script runs from the nix store, so its own path says nothing about where
# the repository (and therefore docs/kanban.md) is.
set -euo pipefail

root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
python="${1:-python3}"
appdir="${2:-$root/modules/home/ai/herdr/plugins/kanban}"

docs="$root/docs/kanban.md"

if [ ! -f "$docs" ]; then
	echo "ERROR: $docs is missing"
	exit 1
fi

# What the plugin actually sends, via the packaged interpreter when one is given.
from_source="$(
	PYTHONPATH="$appdir" "$python" -B -c \
		'from kanban.dispatch import protocol_block; print(protocol_block("<task>"))'
)"

# The docs quote a concrete card id (`this card is K3`); the template takes one.
# Both sides are normalised to the same placeholder so the check is about the
# wording an agent acts on, not about which example id the docs happen to use.
normalise() { sed -E 's/this card is [^ ]+\./this card is <id>./'; }

# What the docs claim, from the first fenced text block that carries the header.
from_docs="$(
	awk '
        /^```text$/ { inside = 1; next }
        inside && /^```$/ { if (found) exit; inside = 0 }
        inside && /^---$/ { found = 1 }
        inside { if (found) print }
    ' "$docs"
)"

if [ -z "$from_docs" ]; then
	echo "ERROR: no protocol block found in docs/kanban.md"
	echo "       (expected a fenced text block starting with ---)"
	exit 1
fi

if ! diff <(printf '%s\n' "$from_source" | normalise) \
	<(printf '%s\n' "$from_docs" | normalise) >/dev/null; then
	echo "ERROR: the protocol in docs/kanban.md is not what the board sends"
	diff <(printf '%s\n' "$from_source" | normalise) \
		<(printf '%s\n' "$from_docs" | normalise) || true
	exit 1
fi

echo "OK: docs/kanban.md protocol is in sync with PROTOCOL_TEMPLATE"
