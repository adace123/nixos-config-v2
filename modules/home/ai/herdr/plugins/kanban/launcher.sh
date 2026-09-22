#!/usr/bin/env bash
#
# herdr-kanban — launcher for the kanban board plugin.
#
#   launcher.sh open [--quick-add]  action: open the board pane
#   launcher.sh board [args...]     pane entrypoint: draw the board
#   launcher.sh sync                startup hook: start the background
#                                   reconciler (`herdr-kanban --sync --detach`)
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
CONFIG_HOME="${HERDR_CONFIG_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/herdr}"
PLUGIN_CONFIG_DIR="${HERDR_PLUGIN_CONFIG_DIR:-$CONFIG_HOME/plugins/config/$PLUGIN_ID}"
CONFIG_FILE="$PLUGIN_CONFIG_DIR/config.toml"

# Popup geometry lives in the plugin config so the manifest's pane entrypoint
# stays static. Overlay is the manifest default and ignores width/height.
read_ui_placement() {
	local prefix="${1:-}"
	UI_PLACEMENT=""
	UI_WIDTH=""
	UI_HEIGHT=""
	[ -f "$CONFIG_FILE" ] || return 0
	# The key *name* is matched, not just its value, so `width` and
	# `quick_add_width` cannot shadow each other.
	UI_PLACEMENT="$(awk -F= -v key="${prefix}placement" '$1 ~ "^[[:space:]]*" key "[[:space:]]*$" {gsub(/[[:space:]\"]/,"",$2); print $2; exit}' "$CONFIG_FILE")"
	UI_WIDTH="$(awk -F= -v key="${prefix}width" '$1 ~ "^[[:space:]]*" key "[[:space:]]*$" {gsub(/[[:space:]\"]/,"",$2); print $2; exit}' "$CONFIG_FILE")"
	UI_HEIGHT="$(awk -F= -v key="${prefix}height" '$1 ~ "^[[:space:]]*" key "[[:space:]]*$" {gsub(/[[:space:]\"]/,"",$2); print $2; exit}' "$CONFIG_FILE")"
}

open_board() {
	local quick="${1:-}" args=()
	if [ "$quick" = "quick" ]; then
		read_ui_placement quick_add_
		args+=(
			--placement "${UI_PLACEMENT:-popup}"
			--width "${UI_WIDTH:-80%}"
			--height "${UI_HEIGHT:-75%}"
			--env "KANBAN_QUICK_ADD=1"
		)
	else
		read_ui_placement
		if [ -n "$UI_PLACEMENT" ]; then
			args+=(--placement "$UI_PLACEMENT")
			if [ "$UI_PLACEMENT" = "popup" ]; then
				args+=(--width "${UI_WIDTH:-95%}" --height "${UI_HEIGHT:-90%}")
			fi
		fi
	fi
	"$HERDR" plugin pane open --plugin "$PLUGIN_ID" --entrypoint board "${args[@]}"
}

run_board() {
	local appdir="$APPDIR" python="$PYTHON"
	case "$appdir" in @*) appdir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" ;; esac
	case "$python" in @*) python="python3" ;; esac
	export PYTHONPATH="$appdir${PYTHONPATH:+:$PYTHONPATH}"
	exec "$python" -m kanban "$@"
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
*)
	printf 'usage: launcher.sh [open [--quick-add] | board [args...] | sync]\n' >&2
	exit 2
	;;
esac
