#!/usr/bin/env bash
# Hand a failed nix-darwin build or activation to omp for diagnosis and repair.
#
# Usage: omp-fix.sh <log-file> [build|switch]
#
#   The stage only shapes the prompt; omp edits the repository either way.
#
# Environment:
#   OMP_FIX=0    do nothing and exit 1 (`OMP_FIX=0 just switch` relies on this)
#   OMP_BIN      omp executable. Defaults to `omp` on PATH; the launchd agent
#                passes an absolute store path because its PATH is minimal.
#   OMP_TIMEOUT  seconds before omp is abandoned (default 1800)
#   REPO_DIR     repository to repair (defaults to this script's parent)
#
# omp runs interactively when a terminal is available so the repair streams
# live; without one (launchd agent) it falls back to non-interactive print
# mode (`-p`). Either way the run is a normal omp session — it is saved under
# `~/.omp/agent/sessions` and shows up in the session list, so a repair can be
# reopened with `omp -r` instead of vanishing. `--auto-approve` lets it edit
# files unattended and `--max-time` bounds the run. Its repair is deliberately
# left UNCOMMITTED:
# the caller decides whether to rebuild and apply, and a human reviews the
# diff. A dirty tree is also what makes the daily auto-update agent skip a
# repository omp has already touched, so a repair cannot loop.
#
# Exit status is omp's: 0 means omp reported a fix.
set -uo pipefail

LOG="${1:?usage: omp-fix.sh <log-file> [build|switch]}"
STAGE="${2:-build}"

if [ "${OMP_FIX:-1}" = "0" ]; then
	echo "omp-fix: OMP_FIX=0, not asking omp to repair. Log: $LOG"
	exit 1
fi

if [ ! -s "$LOG" ]; then
	echo "omp-fix: $LOG is missing or empty — nothing to hand to omp" >&2
	exit 1
fi

REPO_DIR="${REPO_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
OMP="${OMP_BIN:-omp}"

if ! command -v "$OMP" >/dev/null 2>&1; then
	echo "omp-fix: '$OMP' not found — cannot auto-repair. Log: $LOG" >&2
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

# `omp --max-time` bounds every run by itself. The headless path keeps an
# outer watchdog as well, so a wedged binary cannot hold the auto-update
# agent's launchd slot forever. The interactive path deliberately has none:
# `timeout` puts the child in its own process group, so the TUI takes SIGTTIN
# on its first `/dev/tty` read and stops (a hang right after "mode=interactive"),
# and a watchdog that fires mid-turn kills omp before it restores the terminal,
# which leaves its capability replies queued for the shell to echo.
TIMEOUT_BIN=""
for candidate in timeout gtimeout; do
	if command -v "$candidate" >/dev/null 2>&1; then
		TIMEOUT_BIN="$candidate"
		break
	fi
done

cd "$REPO_DIR" || exit 1
echo "omp-fix: handing $STAGE failure to omp ($OMP), log $LOG"

# omp must inherit the shell's own descriptors. Re-opening `/dev/tty` for its
# stdin gives a fresh descriptor whose kqueue registration fails with EINVAL:
# omp logs "terminal disconnected", stops rendering and exits 129 with the
# terminal unrestored, which is what leaves the terminal's capability replies
# (`0u62;22c11;rgb:…`) queued for the shell to echo. `just` hands the real
# terminal through, so isatty is the right test; a piped stdout means the TUI
# would garble the pipe, hence print mode.
if [ -t 0 ] && [ -t 1 ]; then
	echo "omp-fix: mode=interactive (stdin and stdout are terminals)"
	"$OMP" --auto-approve --max-time "${OMP_TIMEOUT:-1800}" "@$LOG" "$PROMPT"
	OMP_STATUS=$?
else
	echo "omp-fix: mode=print (no terminal on stdin and stdout)"
	# Headless (launchd agent): print mode only emits on exit.
	if [ -n "$TIMEOUT_BIN" ]; then
		"$TIMEOUT_BIN" "${OMP_TIMEOUT:-1800}" "$OMP" -p --auto-approve --max-time "${OMP_TIMEOUT:-1800}" "@$LOG" "$PROMPT"
	else
		"$OMP" -p --auto-approve --max-time "${OMP_TIMEOUT:-1800}" "@$LOG" "$PROMPT"
	fi
	OMP_STATUS=$?
fi
if [ "$OMP_STATUS" -ne 0 ]; then
	echo "omp-fix: omp exited with status $OMP_STATUS; log: $LOG" >&2
fi
exit "$OMP_STATUS"
