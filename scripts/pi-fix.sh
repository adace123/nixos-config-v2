#!/usr/bin/env bash
# Hand a failed nix-darwin build or activation to pi for diagnosis and repair.
#
# Usage: pi-fix.sh <log-file> [build|switch]
#
#   The stage only shapes the prompt; pi edits the repository either way.
#
# Environment:
#   PI_FIX=0     do nothing and exit 1 (`PI_FIX=0 just switch` relies on this)
#   PI_BIN       pi executable. Defaults to `pi` on PATH; the launchd agent
#                passes an absolute store path because its PATH is minimal.
#   PI_TIMEOUT   seconds before pi is abandoned (default 1800)
#   REPO_DIR     repository to repair (defaults to this script's parent)
#
# pi runs non-interactively (`-p --no-session --approve`), so it can edit files
# without a terminal. Its repair is deliberately left UNCOMMITTED: the caller
# decides whether to rebuild and apply, and a human reviews the diff. A dirty
# tree is also what makes the daily auto-update agent skip a repository pi has
# already touched, so a repair cannot loop.
#
# Exit status is pi's: 0 means pi reported a fix.
set -uo pipefail

LOG="${1:?usage: pi-fix.sh <log-file> [build|switch]}"
STAGE="${2:-build}"

if [ "${PI_FIX:-1}" = "0" ]; then
	echo "pi-fix: PI_FIX=0, not asking pi to repair. Log: $LOG"
	exit 1
fi

if [ ! -s "$LOG" ]; then
	echo "pi-fix: $LOG is missing or empty — nothing to hand to pi" >&2
	exit 1
fi

REPO_DIR="${REPO_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
PI="${PI_BIN:-pi}"

if ! command -v "$PI" >/dev/null 2>&1; then
	echo "pi-fix: '$PI' not found — cannot auto-repair. Log: $LOG" >&2
	exit 1
fi

case "$STAGE" in
switch)
	PROMPT="The nix-darwin activation in $REPO_DIR failed after the build succeeded; the activation log is attached. Work out the root cause and edit the configuration so activation succeeds. Keep the change minimal. Do not run the switch yourself — the caller re-runs it."
	;;
*)
	PROMPT="The nix-darwin build of $REPO_DIR failed; the build log is attached. Work out the root cause and edit the configuration so it builds again. Keep the change minimal, and follow this repository's conventions for docs and CHANGELOG entries (see AGENTS.md). Do not run the switch yourself — the caller rebuilds."
	;;
esac

# macOS has no coreutils `timeout` by default; an unattended pi must not run
# forever, but a missing watchdog is better than refusing to repair at all.
TIMEOUT_BIN=""
for candidate in timeout gtimeout; do
	if command -v "$candidate" >/dev/null 2>&1; then
		TIMEOUT_BIN="$candidate"
		break
	fi
done

cd "$REPO_DIR" || exit 1
echo "pi-fix: handing $STAGE failure to pi ($PI), log $LOG"

if [ -n "$TIMEOUT_BIN" ]; then
	"$TIMEOUT_BIN" "${PI_TIMEOUT:-1800}" "$PI" -p --no-session --approve "@$LOG" "$PROMPT"
else
	"$PI" -p --no-session --approve "@$LOG" "$PROMPT"
fi
