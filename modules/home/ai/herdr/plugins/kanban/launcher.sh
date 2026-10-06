#!/usr/bin/env bash
#
# herdr-kanban — launcher for the kanban board plugin.
#
#   launcher.sh open [--quick-add]  action: open the board pane
#   launcher.sh board [args...]     pane entrypoint: draw the board
#   launcher.sh sync                startup hook: start the background
#                                   reconciler (`herdr-kanban --sync --detach`)
#   launcher.sh sync-stop           stop it (activation, before restarting it)
#
# The board is a Textual app. Its Python package lives in the Nix store
# (@APPDIR@) and is run with the interpreter from
# `python3.withPackages [ textual ]` (@PYTHON@); herdr.nix substitutes both
# placeholders when it packages this script. Unsubstituted placeholders (a
# plain checkout, `kanban …` by hand) fall back to the script's own directory
# and the `python3` on PATH.
set -euo pipefail

PYTHON="@PYTHON@"
APPDIR="@APPDIR@"

PLUGIN_ID="herdr-kanban"
HERDR="${HERDR_BIN_PATH:-herdr}"

# The interpreter and package the launcher runs. Resolved in one place so the
# board and the pane-geometry call below cannot drift; an unsubstituted
# placeholder (a plain checkout, `kanban …` by hand) falls back to the script's
# own directory and the `python3` on PATH.
RUN_PYTHON=""
RUN_APPDIR=""
resolve_runner() {
	RUN_PYTHON="$PYTHON"
	RUN_APPDIR="$APPDIR"
	case "$RUN_APPDIR" in @*) RUN_APPDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" ;; esac
	case "$RUN_PYTHON" in @*) RUN_PYTHON="python3" ;; esac
}

kanban_module() {
	resolve_runner
	PYTHONPATH="$RUN_APPDIR${PYTHONPATH:+:$PYTHONPATH}" "$RUN_PYTHON" -m kanban "$@"
}

open_board() {
	local quick="${1:-}" out="" arg args=()
	# Popup geometry lives in the plugin config so the manifest's pane entrypoint
	# stays static. Python owns that file's parsing (`--pane-open-args`), so the
	# shell never re-reads a TOML key with awk; it only reads the flags back, one
	# per line, which cannot be split mid-value.
	if [ "$quick" = "quick" ]; then
		out="$(kanban_module --pane-open-args --quick-add)" || return 1
	else
		out="$(kanban_module --pane-open-args)" || return 1
	fi
	while IFS= read -r arg; do
		if [ -n "$arg" ]; then
			args+=("$arg")
		fi
	done <<<"$out"
	"$HERDR" plugin pane open --plugin "$PLUGIN_ID" --entrypoint board "${args[@]}"
}

run_board() {
	resolve_runner
	export PYTHONPATH="$RUN_APPDIR${PYTHONPATH:+:$PYTHONPATH}"
	exec "$RUN_PYTHON" -m kanban "$@"
}

case "${1:-open}" in
open)
	shift || true
	case "${1:-}" in
	--quick-add | quick-add | quick) open_board quick ;;
	*) open_board ;;
	esac
	;;
board)
	shift || true
	run_board "$@"
	;;
sync)
	# Same interpreter and package as the board; the daemon forks away and this
	# returns at once, so herdr's startup hook completes.
	run_board --sync --detach
	;;
sync-stop)
	run_board --sync-stop
	;;
*)
	printf 'usage: launcher.sh [open [--quick-add] | board [args...] | sync | sync-stop]\n' >&2
	exit 2
	;;
esac
