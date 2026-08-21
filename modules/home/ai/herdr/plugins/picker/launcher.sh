#!/usr/bin/env bash
#
# herdr-picker - a herdr .sh plugin: a generic fuzzy picker over herdr spaces,
# sessions, git worktrees, custom commands, and agent panes.
#
#   launcher.sh                menu: pick a category, then an item
#   launcher.sh <category>     open the picker straight into a category
#                              (spaces | sessions | worktrees | commands | agents)
#   launcher.sh open [cat]     action entrypoint: open the picker popup
#   launcher.sh pick           pane entrypoint: draw the tv/fzf picker
#   launcher.sh rows <cat>     emit rows for tv, as <idx>\t<run>\t<label>\t<badge>
#
# Commands run scoped to the directory you launched from (HERDR_LAUNCHER_CWD).
# Categories:
#   spaces     - herdr workspaces           (open: focus the workspace)
#   sessions   - named herdr sessions       (open: attach to the session)
#   worktrees  - <repo>/.git worktrees      (open: focus or open the worktree)
#   commands   - global config.toml `[[keys.command]]` + <repo>/.herdr-picker.toml
#   agents     - herdr agent panes          (open: focus the agent)
#
# Env:
#   HERDR_BIN_PATH     herdr binary (injected by herdr)
#   HERDR_LAUNCHER_CWD directory to scope to (set by open_pane)
#   MODE               category to start in (set by open_pane; default menu)
set -euo pipefail

HERDR="${HERDR_BIN_PATH:-herdr}"
PLUGIN_ID="herdr-picker"

HERDR_CONFIG_HOME="${HERDR_CONFIG_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/herdr}"
CONFIG_TOML="${HERDR_CONFIG_TOML:-$HERDR_CONFIG_HOME/config.toml}"

# --- rows: <idx>\t<run>\t<label>\t<badge> ---------------------------------

rows_menu() {
	local i=0
	i=$((i + 1))
	printf '%d\tmenu:spaces\tSpaces\tmenu\n' "$i"
	i=$((i + 1))
	printf '%d\tmenu:worktrees\tWorktrees\tmenu\n' "$i"
	i=$((i + 1))
	printf '%d\tmenu:commands\tCommands\tmenu\n' "$i"
	i=$((i + 1))
	printf '%d\tmenu:agents\tAgents\tmenu\n' "$i"
	i=$((i + 1))
	printf '%d\tmenu:sessions\tSessions\tmenu\n' "$i"
}

rows_spaces() {
	local i=0 id label
	while IFS=$'\t' read -r id label; do
		i=$((i + 1))
		printf '%d\t"%s" workspace focus %s\t%s\tspace\n' "$i" "$HERDR" "$id" "$label"
	done < <("$HERDR" workspace list 2>/dev/null | jq -r '.result.workspaces[] | [.workspace_id,.label] | @tsv')
}

rows_agents() {
	local i=0 name status
	while IFS=$'\t' read -r name status; do
		i=$((i + 1))
		printf '%d\t"%s" agent focus %s\t%s\t%s\n' "$i" "$HERDR" "$name" "$name" "$status"
	done < <("$HERDR" agent list 2>/dev/null | jq -r '.result.agents[] | [.agent,.agent_status] | @tsv')
}

rows_sessions() {
	local i=0 name running status run
	while IFS=$'\t' read -r name running _; do
		i=$((i + 1))
		status="stopped"
		[ "$running" = true ] && status="running"
		run="\"$HERDR\" session attach \"$name\""
		printf '%d\t%s\t%s\t%s\n' "$i" "$run" "$name" "$status"
	done < <("$HERDR" session list --json 2>/dev/null | jq -r '.sessions[] | [.name, (.running | tostring), .session_dir] | @tsv')
}

rows_worktrees() {
	local i=0 branch label path open_ws base run
	base="${HERDR_LAUNCHER_CWD:-$PWD}"
	while IFS=$'\t' read -r branch label path open_ws; do
		i=$((i + 1))
		if [ -n "$open_ws" ]; then
			run="\"$HERDR\" workspace focus $open_ws"
		else
			run="\"$HERDR\" worktree open --cwd \"$base\" --path \"$path\" --focus"
		fi
		[ -n "$label" ] || label="$branch"
		printf '%d\t%s\t%s\tworktree\n' "$i" "$run" "$label"
	done < <("$HERDR" worktree list --cwd "$base" 2>/dev/null |
		jq -r '.result.worktrees[] | [.branch,.label,.path,(.open_workspace_id // "")] | @tsv')
}

# Parse [[keys.command]] blocks from one herdr-style toml into TSV lines of
#   <run>\t<label>\t<close_on_exit>
# label = description (falls back to the command); entries that just trigger
# another plugin action (type = "plugin_action") are skipped so the picker
# doesn't list itself or its peers.
extract_from_file() {
	local file="$1"
	awk '
    function emit() {
      if (cmd == "" || typ == "plugin_action") return
      if (desc == "") desc = cmd
      print cmd "\t" desc "\t" close_value
    }
    BEGIN { in_cmd = 0; key = ""; cmd = ""; desc = ""; typ = "popup"; close_value = "" }
    /^\[\[keys\.command\]\]/ { emit(); in_cmd = 1; key = ""; cmd = ""; desc = ""; typ = "popup"; close_value = ""; next }
    /^\[/ { emit(); in_cmd = 0; next }
    {
      if (!in_cmd) next
      if ($0 ~ /^key[[:space:]]*=[[:space:]]*"/) {
        v = $0; sub(/^key[[:space:]]*=[[:space:]]*"/, "", v); sub(/"[[:space:]]*$/, "", v); key = v; next
      }
      if ($0 ~ /^command[[:space:]]*=[[:space:]]*"/) {
        v = $0; sub(/^command[[:space:]]*=[[:space:]]*"/, "", v); sub(/"[[:space:]]*$/, "", v); cmd = v; next
      }
      if ($0 ~ /^type[[:space:]]*=[[:space:]]*"/) {
        v = $0; sub(/^type[[:space:]]*=[[:space:]]*"/, "", v); sub(/"[[:space:]]*$/, "", v); typ = v; next
      }
      if ($0 ~ /^close_on_exit[[:space:]]*=/) {
        v = $0; sub(/^[^=]*=[[:space:]]*/, "", v); gsub(/[[:space:]\"]/, "", v); close_value = tolower(v); next
      }
      if ($0 ~ /^description[[:space:]]*=[[:space:]]*"/) {
        v = $0; sub(/^description[[:space:]]*=[[:space:]]*"/, "", v); sub(/"[[:space:]]*$/, "", v); desc = v; next
      }
    }
    END { emit() }
  ' "$file"
}

# Project-local commands file: <project-root>/.herdr-picker.toml, where the
# project root is the nearest enclosing git repository (falls back to the launch
# directory). Same [[keys.command]] format as the global config.toml.
project_config_file() {
	local base="$1" root
	root="$(git -C "$base" rev-parse --show-toplevel 2>/dev/null || true)"
	[ -n "$root" ] || root="$base"
	if [ -f "$root/.herdr-picker.toml" ]; then
		printf '%s' "$root/.herdr-picker.toml"
	fi
}

# Build the commands list as TSV rows <idx>\t<run>\t<label>\t<badge>\t<close_on_exit>:
# project commands (badge "project") first, then global [[keys.command]] entries.
# A command-level close_on_exit value is carried as the optional fifth field.
rows_commands() {
	local base="${HERDR_LAUNCHER_CWD:-$PWD}" i=0 run label proj_file
	proj_file="$(project_config_file "$base")"
	if [ -n "$proj_file" ] && [ -f "$proj_file" ]; then
		while IFS=$'\t' read -r run label close; do
			i=$((i + 1))
			printf '%d\t%s\t%s\tproject\t%s\n' "$i" "$run" "$label" "$close"
		done < <(extract_from_file "$proj_file")
	fi
	while IFS=$'\t' read -r run label close; do
		i=$((i + 1))
		printf '%d\t%s\t%s\tglobal\t%s\n' "$i" "$run" "$label" "$close"
	done < <(extract_from_file "$CONFIG_TOML")
}

rows_for() {
	case "$1" in
	menu) rows_menu ;;
	spaces) rows_spaces ;;
	worktrees) rows_worktrees ;;
	commands) rows_commands ;;
	agents) rows_agents ;;
	sessions) rows_sessions ;;
	*) rows_menu ;;
	esac
}

# --- opening the popup ------------------------------------------------------

# Read popup size and the default close behavior from the plugin's own config
# ($HERDR_PLUGIN_CONFIG_DIR/config.toml), seeding defaults on first use.
# width/height accept terminal cells (integer) or a percentage like "80%".
read_width_height() {
	local cfg default_w default_h default_close w h close_value
	default_w="60%"
	default_h='"50%"'
	default_close=true
	PCK_WIDTH="$default_w"
	PCK_HEIGHT="$default_h"
	PCK_CLOSE_ON_EXIT="$default_close"
	if [ -n "${HERDR_PLUGIN_CONFIG_DIR:-}" ]; then
		cfg="$HERDR_PLUGIN_CONFIG_DIR/config.toml"
		if [ ! -f "$cfg" ]; then
			mkdir -p "$HERDR_PLUGIN_CONFIG_DIR"
			cat >"$cfg" <<EOF
# herdr-picker settings
#
# Popup width/height accept terminal cells (integer) or a percentage such as
# "80%". Re-open the picker after editing to apply.
[ui]
width = "${default_w}"
height = ${default_h}
close_on_exit = ${default_close}
EOF
		fi
		w="$(awk -F= '/^[[:space:]]*width[[:space:]]*=/{gsub(/[[:space:]\"]/,"",$2); print $2; exit}' "$cfg")"
		h="$(awk -F= '/^[[:space:]]*height[[:space:]]*=/{gsub(/[[:space:]\"]/,"",$2); print $2; exit}' "$cfg")"
		close_value="$(awk -F= '/^[[:space:]]*close_on_exit[[:space:]]*=/{gsub(/[[:space:]\"]/,"",$2); print tolower($2); exit}' "$cfg")"
		[ -n "$w" ] && PCK_WIDTH="$w"
		[ -n "$h" ] && PCK_HEIGHT="$h"
		case "$close_value" in
		false | 0 | no | off) PCK_CLOSE_ON_EXIT=false ;;
		esac
	fi
}

open_pane() {
	local category="${1:-menu}" cwd env_args=()
	read_width_height
	# Scoped directory = the pane that fired the action (from herdr's context).
	cwd="$(current_dir)"
	[ -n "$cwd" ] && env_args+=(--env "HERDR_LAUNCHER_CWD=$cwd")
	env_args+=(--env "MODE=$category")
	# Popup size comes from the plugin config (--width/--height are supported by
	# `plugin pane open` even though they don't show in --help). No --placement:
	# popup placement comes from the manifest pane entrypoint.
	"$HERDR" plugin pane open \
		--plugin "$PLUGIN_ID" \
		--entrypoint launch \
		--width "$PCK_WIDTH" \
		--height "$PCK_HEIGHT" \
		"${env_args[@]}"
}

# Working directory of the pane that fired the action, from herdr's injected
# context (falls back to the workspace cwd, then empty).
current_dir() {
	local raw v
	raw="${HERDR_PLUGIN_CONTEXT_JSON:-}"
	[ -n "$raw" ] || return 0
	v="$(printf '%s' "$raw" | sed -n 's/.*"focused_pane_cwd"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)"
	[ -n "$v" ] || v="$(printf '%s' "$raw" | sed -n 's/.*"workspace_cwd"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)"
	printf '%s' "$v"
}

# --- interactive picking -----------------------------------------------------

pick() {
	local tv_bin fzf_bin chosen cwd category selected_idx selected_row item_close
	tv_bin="$(command -v tv || true)"
	fzf_bin="$(command -v fzf || true)"
	if [ -z "$tv_bin" ] && [ -z "$fzf_bin" ]; then
		printf 'herdr-picker: need tv (television) or fzf on PATH\n' >&2
		exit 1
	fi
	category="${MODE:-menu}"
	cwd="${HERDR_LAUNCHER_CWD:-$PWD}"
	read_width_height

	# Two-stage loop: a menu selection returns "menu:<cat>", which switches the
	# category and re-opens the picker for that category's items.
	while :; do
		if [ -n "$tv_bin" ]; then
			chosen="$(
				"$tv_bin" --no-remote \
					--source-command="bash $0 rows $category" \
					--source-display='{split:\t:2}  [{split:\t:3}]' \
					--source-output='{split:\t:0}' \
					--preview-command='printf "Label: %s\\nSource: %s\\n\\n%s\\n" "{split:\t:2}" "{split:\t:3}" "{split:\t:1}"' \
					--preview-header="Scope: $cwd" \
					--preview-size=55 \
					--preview-word-wrap \
					--input-header="$category — $cwd" \
					--input-prompt='> '
			)" || true
		else
			chosen="$(fzf_select "$fzf_bin" "$category")" || true
		fi
		[ -n "$chosen" ] || exit 0 # Esc / empty → cancel
		selected_idx="$chosen"
		selected_row="$(rows_for "$category" | awk -F '\t' -v i="$selected_idx" '$1 == i && !found { print; found = 1 }')"
		chosen="$(printf '%s\n' "$selected_row" | cut -f2)"
		item_close="$(printf '%s\n' "$selected_row" | cut -f5)"
		[ -n "$chosen" ] || exit 0
		if [[ $chosen == menu:* ]]; then
			category="${chosen#menu:}"
			continue
		fi
		case "$item_close" in
		false | 0 | no | off) PCK_CLOSE_ON_EXIT=false ;;
		true | 1 | yes | on) PCK_CLOSE_ON_EXIT=true ;;
		esac
		break
	done

	printf '\n\033[2m$ %s [%s]\033[0m\n' "$chosen" "$cwd"
	# Scope to the launching directory, then run the choice in this popup pane;
	# herdr tears the popup down when it exits.
	cd "$cwd" 2>/dev/null || true
	set +e
	eval -- "$chosen"
	local command_status=$?
	set -e

	if [ "$PCK_CLOSE_ON_EXIT" = false ]; then
		printf '\nPress Enter to close the picker...\n'
		IFS= read -r _ </dev/tty || true
	fi

	return "$command_status"
}

# fzf fallback: display "label [badge]" (row index hidden), recover the run by
# its index afterwards.
fzf_select() {
	local fzf_bin="$1" cat="$2" rows idx
	rows="$(rows_for "$cat")"
	[ -n "$rows" ] || return 0
	idx="$(
		printf '%s\n' "$rows" | awk -F '\t' '{ printf "%s\t%s [%s]\n", $1, $3, $4 }' |
			"$fzf_bin" --layout=reverse --delimiter='\t' --with-nth=2 --prompt='> '
	)" || return 0
	[ -n "$idx" ] || return 0
	idx="${idx%%$'\t'*}"
	printf '%s' "$idx"
}

case "${1:-}" in
"" | "menu") open_pane menu ;;
spaces | sessions | worktrees | commands | agents) open_pane "$1" ;;
open) open_pane "${2:-menu}" ;;
pick) pick ;;
rows) rows_for "${2:-${MODE:-menu}}" ;;
*)
	printf 'usage: launcher.sh [spaces|sessions|worktrees|commands|agents]\n' >&2
	exit 2
	;;
esac
