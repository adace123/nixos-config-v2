#!/usr/bin/env bash
#
# herdr-automations - cron-scheduled herdr automations (shepherd-inspired).
#
#   automations.sh daemon [--detach]  run the scheduler (startup hook uses --detach)
#   automations.sh tick               run a single scheduling tick (debugging)
#   automations.sh list               table: name, schedule, enabled, last/next run
#   automations.sh status             daemon liveness + the list table
#   automations.sh show <name>        details view with run/enable/open actions
#   automations.sh repos [...]        manage the repo registry (list/add/remove)
#   automations.sh history [name]     newest-first run history from the log
#   automations.sh open <name>        focus the workspace of the last run
#   automations.sh run <name>         fire an automation now (manual trigger)
#   automations.sh new                guided wizard: create a new automation
#   automations.sh enable <name>      set enabled = true (in-place edit)
#   automations.sh disable <name>     set enabled = false (in-place edit)
#   automations.sh board [--once]     live htop-style table (static with --once)
#   automations.sh rows               picker rows: <idx>\t<run>\t<label>\t<badge>
#
# Automations live in repo files (<repo>/.herdr-automations.toml, one
# [[automation]] block each) plus the legacy global dir (<config>/automations/
# *.toml, one flat automation per file). Names must be unique across all
# sources. Each entry:
#
#   name = "morning-digest"         # required: no whitespace, /, \, or leading .
#   description = "Weekday digest"  # optional: shown in list/picker/notifications
#   cron = "15 6 * * 1-5"           # required: 5-field cron (min hour dom mon dow),
#                               # or @hourly/@daily/@weekly/@monthly/@yearly
#   workspace = "ops"               # required: herdr workspace label for runs
#   agent = "claude"                # required: herdr agent kind (claude|codex|pi|...)
#   model = "sonnet"                # optional: passed as `--model` (allowlisted kinds)
#   agent_args = ["--verbose"]      # optional: verbatim extra args for `herdr agent start`
#   auto_close = true               # optional: close the workspace when the run ends
#   watch_minutes = 240             # optional: give up watching after N minutes (1-1440)
#   command = "Do the thing."       # required: submitted via `herdr agent prompt`
#   directory = "~/projects/ops"    # optional cwd when creating the workspace
#   enabled = true                  # optional, default true (omitted = live)
#
# Semantics (mirroring herdr-shepherd):
# - The daemon ticks once a minute, aligned to the minute boundary, and
#   re-reads every file each tick: edits apply with no restart.
# - No backfill: only the current minute fires. Waking a slept machine does
#   not run missed schedules.
# - No overlap: the run lock is held for the whole run, so a scheduled fire
#   skips while the previous run is still active and a manual `run` refuses
#   too (mkdir locks under the state dir; the kernel-independent equivalent
#   of shepherd's flock, portable to macOS which has no flock(1)). Stale
#   locks from dead holders are stolen on sight.
# - One daemon: a daemon lock dir keeps two schedulers from double-firing.
# - Runs stay visible: each fire opens/focuses the workspace and leaves the
#   session there for review, unless the entry sets auto_close = true.
# - The run's pane gets HERDR_AUTOMATION=<name> and HERDR_TRIGGER=<trigger>
#   in its environment, so prompts can tell schedule/manual apart.
#
# The daemon talks to herdr over its socket, so it must inherit
# HERDR_SOCKET_PATH: start it from inside herdr (the [[startup]] hook does
# this on every server start). Started elsewhere it exits with a clear error.
set -euo pipefail

HERDR="${HERDR_BIN_PATH:-herdr}"
PLUGIN_ID="herdr-automations"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
SCRIPT="$SCRIPT_DIR/automations.sh"

# --- paths ---------------------------------------------------------------
# Inside herdr these are the injected plugin dirs. Outside plugin context the
# CLI asks herdr for its managed config dir so `list`/`status` agree with the
# daemon; XDG-style fallbacks apply only when herdr itself is unreachable.
resolve_paths() {
	CONFIG_DIR="${HERDR_PLUGIN_CONFIG_DIR:-}"
	STATE_DIR="${HERDR_PLUGIN_STATE_DIR:-}"
	if [ -z "$CONFIG_DIR" ]; then
		if dir="$("$HERDR" plugin config-dir "$PLUGIN_ID" 2>/dev/null)"; then
			[ -n "$dir" ] && CONFIG_DIR="$dir"
		fi
	fi
	: "${CONFIG_DIR:=${XDG_CONFIG_HOME:-$HOME/.config}/herdr-automations}"
	if [ -z "$STATE_DIR" ]; then
		case "$CONFIG_DIR" in
		*/plugins/config/*)
			STATE_DIR="$HOME/.local/state/herdr/plugins/$PLUGIN_ID"
			;;
		*)
			: "${STATE_DIR:=${XDG_STATE_HOME:-$HOME/.local/state}/herdr-automations}"
			;;
		esac
	fi
	ACTIONS_DIR="$CONFIG_DIR/automations"
	LOG_FILE="$STATE_DIR/automations.log"
	PID_FILE="$STATE_DIR/daemon.pid"
}

# --- logging ---------------------------------------------------------------
rotate_log() {
	local size=0
	[ -f "$LOG_FILE" ] && size="$(wc -c <"$LOG_FILE" | tr -d ' ')"
	if [ "${size:-0}" -gt 5242880 ]; then
		mv -f "$LOG_FILE" "$LOG_FILE.1"
	fi
}

log_msg() {
	rotate_log
	printf '%s\t%s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$*" >>"$LOG_FILE"
}

notify() {
	"$HERDR" notification show "$1" --body "$2" >/dev/null 2>&1 || true
}

# --- TOML parsing ----------------------------------------------------------
# Flat single-line parser: fills A_name/A_cron/A_workspace/A_agent/A_command/
# A_directory/A_enabled or sets A_error. Values may be
# double-quoted, single-quoted, or bare (true/false). Unknown keys and missing
# required keys are errors (rejected, not clamped — a silently adjusted
# schedule would run at a time nobody asked for).
parse_entry() {
	# $1=file $2=block (0 = whole flat file, else 1-based [[automation]] index).
	# Parses one automation entry into A_* (or A_error on any problem).
	local file="$1" block="${2:-0}" tsv key val
	A_name=""
	A_cron=""
	A_workspace=""
	A_agent=""
	A_command=""
	A_directory=""
	A_enabled="true"
	A_description=""
	A_model=""
	A_agent_args=""
	A_auto_close="false"
	A_watch_minutes="240"
	A_error=""
	tsv="$(awk -v blk="$block" '
    function unquote(v) {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", v)
      if (v ~ /^".*"$/) { sub(/^"/, "", v); sub(/"$/, "", v) }
      else if (v ~ /^'\''.*'\''$/) { sub(/^'\''/, "", v); sub(/'\''$/, "", v) }
      return v
    }
    # strip trailing comments outside quotes
    function strip_comment(line,   i, c, in_d, in_s, out) {
      in_d = 0; in_s = 0; out = ""
      for (i = 1; i <= length(line); i++) {
        c = substr(line, i, 1)
        if (c == "\"" && !in_s) in_d = !in_d
        else if (c == "'"'"'" && !in_d) in_s = !in_s
        else if (c == "#" && !in_d && !in_s) break
        out = out c
      }
      return out
    }
    BEGIN { inb = (blk == 0) }
    /^\[\[automation\]\]/ { b++; inb = (b == blk); next }
    !inb { next }
    /^[[:space:]]*#/ { next }
    /^[[:space:]]*$/ { next }
    /^\[/ { next }
    /=/ {
      line = strip_comment($0)
      n = split(line, parts, "=")
      k = parts[1]; gsub(/^[[:space:]]+|[[:space:]]+$/, "", k)
      v = substr(line, index(line, "=") + 1)
      print k "\t" unquote(v)
    }
  ' "$file")" || {
		A_error="cannot read file"
		return 0
	}
	while IFS=$'\t' read -r key val; do
		[ -n "$key" ] || continue
		case "$key" in
		name) A_name="$val" ;;
		cron) A_cron="$val" ;;
		workspace) A_workspace="$val" ;;
		agent) A_agent="$val" ;;
		command) A_command="$val" ;;
		model) A_model="$val" ;;
		agent_args) A_agent_args="$val" ;;
		directory) A_directory="$val" ;;
		description) A_description="$val" ;;
		auto_close)
			case "$(printf '%s' "$val" | tr '[:upper:]' '[:lower:]')" in
			true | 1 | yes | on) A_auto_close="true" ;;
			false | 0 | no | off) A_auto_close="false" ;;
			*) A_error="bad auto_close value: $val" ;;
			esac
			;;
		watch_minutes)
			case "$val" in
			'' | *[!0-9]*) A_error="bad watch_minutes value: $val" ;;
			*)
				if [ "$val" -ge 1 ] && [ "$val" -le 1440 ]; then
					A_watch_minutes="$val"
				else
					A_error="watch_minutes out of range 1-1440: $val"
				fi
				;;
			esac
			;;
		enabled)
			case "$(printf '%s' "$val" | tr '[:upper:]' '[:lower:]')" in
			true | 1 | yes | on) A_enabled="true" ;;
			false | 0 | no | off) A_enabled="false" ;;
			*) A_error="bad enabled value: $val" ;;
			esac
			;;
		*) A_error="unknown key: $key" ;;
		esac
	done <<<"$tsv"
	[ -n "$A_error" ] && return 0
	for key in name cron workspace agent command; do
		case "$key" in
		name) val="$A_name" ;;
		cron) val="$A_cron" ;;
		workspace) val="$A_workspace" ;;
		agent) val="$A_agent" ;;
		command) val="$A_command" ;;
		esac
		if [ -z "$val" ]; then
			A_error="missing required key: $key"
			return 0
		fi
	done
	case "$A_name" in
	*[[:space:]/\\]* | .*)
		A_error="bad name (no whitespace, /, \\, or leading .): $A_name"
		return 0
		;;
	esac
	if [ -n "$A_model" ]; then
		case "$A_agent" in
		claude | codex | opencode | gemini) ;;
		*)
			A_error="model needs a kind accepting --model (claude|codex|opencode|gemini); use agent_args for $A_agent"
			return 0
			;;
		esac
	fi
	if [ -n "$A_agent_args" ] && ! parse_string_list "$A_agent_args"; then
		A_error="bad agent_args (want [\"--flag\", \"...\"]): $A_agent_args"
		return 0
	fi
	validate_cron "$A_cron" || return 0
	return 0
}

# --- cron ------------------------------------------------------------------
# 5-field cron matcher: minute hour day-of-month month day-of-week.
# Fields accept *, */n, a-b, a-b/n, lists, and single values. DOW accepts
# 0-7 (7 = Sunday). DOM-vs-DOW follows standard cron OR semantics: when both
# are restricted, matching either fires.
cron_expand() {
	# Nicknames to 5-field expressions (display keeps the original).
	case "$1" in
	@hourly) printf '0 * * * *' ;;
	@daily | @midnight) printf '0 0 * * *' ;;
	@weekly) printf '0 0 * * 0' ;;
	@monthly) printf '0 0 1 * *' ;;
	@yearly | @annually) printf '0 0 1 1 *' ;;
	*) printf '%s' "$1" ;;
	esac
}

cron_num_ok() {
	local v="$1" min="$2" max="$3"
	case "$v" in
	'' | *[!0-9]*) return 1 ;;
	esac
	[ "$v" -ge "$min" ] && [ "$v" -le "$max" ]
}

cron_part_ok() {
	# $1=value $2=single-or-range-part $3=min $4=max
	local value="$1" part="$2" min="$3" max="$4" lo hi step i d
	step=1
	case "$part" in
	*/*)
		step="${part#*/}"
		part="${part%%/*}"
		cron_num_ok "$step" 1 1000000 || return 1
		;;
	esac
	if [ "$part" = "*" ] || [ -z "$part" ]; then
		lo="$min"
		hi="$max"
	elif [[ $part == *-* ]]; then
		lo="${part%%-*}"
		hi="${part##*-}"
		if [ "$min" -eq 0 ] && [ "$max" -eq 6 ]; then
			# day-of-week: 7 is Sunday
			case "$lo" in 7) lo=0 ;; esac
			case "$hi" in 7) hi=0 ;; esac
		fi
		cron_num_ok "$lo" "$min" "$max" || return 1
		cron_num_ok "$hi" "$min" "$max" || return 1
		if [ "$lo" -gt "$hi" ]; then
			if [ "$min" -eq 0 ] && [ "$max" -eq 6 ]; then
				# wrapped week range (e.g. 5-1): walk continuously
				i="$lo"
				while [ "$i" -le $((hi + 7)) ]; do
					d=$((i % 7))
					if [ "$value" -eq "$d" ] && [ $(((i - lo) % step)) -eq 0 ]; then
						return 0
					fi
					i=$((i + 1))
				done
				return 1
			fi
			return 1
		fi
	else
		if [ "$min" -eq 0 ] && [ "$max" -eq 6 ]; then
			case "$part" in 7) part=0 ;; esac
		fi
		cron_num_ok "$part" "$min" "$max" || return 1
		lo="$part"
		hi="$part"
	fi
	i="$lo"
	while [ "$i" -le "$hi" ]; do
		if [ "$value" -eq "$i" ] && [ $(((i - lo) % step)) -eq 0 ]; then
			return 0
		fi
		i=$((i + 1))
	done
	return 1
}

cron_field_ok() {
	# $1=value $2=field $3=min $4=max
	local value="$1" field="$2" min="$3" max="$4" part old_ifs
	[ "$field" = "*" ] && return 0
	old_ifs="$IFS"
	IFS=','
	set -f
	# shellcheck disable=SC2162
	for part in $field; do
		IFS="$old_ifs"
		if cron_part_ok "$value" "$part" "$min" "$max"; then
			IFS="$old_ifs"
			set +f
			return 0
		fi
		IFS=','
	done
	IFS="$old_ifs"
	set +f
	return 1
}

cron_norm_dow() {
	# Normalise DOW 7 -> 0 for lists and singletons (portable: no \b on BSD sed).
	local f=",$1,"
	f="$(printf '%s' "$f" | sed 's/,7,/,0,/g')"
	f="${f#,}"
	f="${f%,}"
	printf '%s' "$f"
}

cron_dom_dow_ok() {
	# $1=dom-field $2=dow-field $3=dom $4=dow: standard cron OR semantics.
	if [ "$1" = "*" ] && [ "$2" = "*" ]; then
		return 0
	elif [ "$1" = "*" ]; then
		cron_field_ok "$4" "$2" 0 6
	elif [ "$2" = "*" ]; then
		cron_field_ok "$3" "$1" 1 31
	else
		cron_field_ok "$3" "$1" 1 31 || cron_field_ok "$4" "$2" 0 6
	fi
}

cron_fields_match() {
	# $1..$5=fields, $6..$10=min hour dom mon dow. No splitting, no clock.
	local f5
	f5="$(cron_norm_dow "$5")"
	cron_field_ok "$6" "$1" 0 59 || return 1
	cron_field_ok "$7" "$2" 0 23 || return 1
	cron_field_ok "$9" "$4" 1 12 || return 1
	cron_dom_dow_ok "$3" "$f5" "$8" "${10}"
}

cron_match() {
	# $1=expr $2=min $3=hour $4=dom $5=mon $6=dow(0-6)
	local expr v_min="$2" v_hour="$3" v_dom="$4" v_mon="$5" v_dow="$6"
	expr="$(cron_expand "$1")"
	local f1 f2 f3 f4 f5
	set -f
	# shellcheck disable=SC2086
	set -- $expr
	set +f
	[ $# -eq 5 ] || return 1
	f1="$1"
	f2="$2"
	f3="$3"
	f4="$4"
	f5="$5"
	cron_fields_match "$f1" "$f2" "$f3" "$f4" "$f5" "$v_min" "$v_hour" "$v_dom" "$v_mon" "$v_dow"
}

validate_cron() {
	local expr field min max old_ifs part part_step part_base ok
	expr="$(cron_expand "$1")"
	local fields mins maxs i
	set -f
	# shellcheck disable=SC2086
	set -- $expr
	set +f
	if [ $# -ne 5 ]; then
		A_error="bad cron (need 5 fields): $expr"
		return 1
	fi
	fields="$1 $2 $3 $4 $5"
	mins="0 0 1 1 0"
	maxs="59 23 31 12 7"
	i=0
	set -f
	for field in $fields; do
		i=$((i + 1))
		min="$(printf '%s' "$mins" | cut -d' ' -f"$i")"
		max="$(printf '%s' "$maxs" | cut -d' ' -f"$i")"
		old_ifs="$IFS"
		IFS=','
		ok=true
		# shellcheck disable=SC2162
		for part in $field; do
			IFS="$old_ifs"
			part_step="${part#*/}"
			part_base="${part%%/*}"
			if [ "$part" != "$part_base" ]; then
				cron_num_ok "$part_step" 1 1000000 || ok=false
			fi
			if [ "$part_base" != "*" ] && [ -n "$part_base" ]; then
				if [[ $part_base == *-* ]]; then
					cron_num_ok "${part_base%%-*}" "$min" "$max" || ok=false
					cron_num_ok "${part_base##*-}" "$min" "$max" || ok=false
				else
					cron_num_ok "$part_base" "$min" "$max" || ok=false
				fi
			fi
			IFS=','
		done
		IFS="$old_ifs"
		if [ "$ok" != true ]; then
			set +f
			A_error="bad cron field $i: $field"
			return 1
		fi
	done
	set +f
	return 0
}

# --- next occurrence -----------------------------------------------------------
# Calendar math goes through date_flavor/ts_parts/mktime_ymdhm so the same
# code runs on GNU and BSD date. Day and month jumps keep the scan cheap: a
# yearly schedule resolves in hundreds of iterations, not hundreds of
# thousands of minute steps. DST edge cases resolve forward (a skipped hour
# simply never matches; a repeated hour is walked through), never looping.
date_flavor() {
	if [ -z "${DATE_FLAVOR:-}" ]; then
		if date -d "@0" +%s >/dev/null 2>&1; then
			DATE_FLAVOR=GNU
		else
			DATE_FLAVOR=BSD
		fi
	fi
	printf '%s' "$DATE_FLAVOR"
}

ts_parts() {
	# $1=epoch -> "Y m d H M dow" (zero-padded except dow).
	if [ "$(date_flavor)" = "GNU" ]; then
		date -d "@$1" '+%Y %m %d %H %M %w'
	else
		date -r "$1" '+%Y %m %d %H %M %w'
	fi
}

mktime_ymdhm() {
	# $1..$5=Y m d H M -> epoch. Inputs must be a valid local time.
	if [ "$(date_flavor)" = "GNU" ]; then
		date -d "$1-$2-$3 $4:$5" +%s
	else
		date -j -f "%Y-%m-%d %H:%M" "$1-$2-$3 $4:$5" +%s
	fi
}

date_fmt() {
	# $1=epoch $2=format -> formatted local time.
	if [ "$(date_flavor)" = "GNU" ]; then
		date -d "@$1" "+$2"
	else
		date -r "$1" "+$2"
	fi
}

cron_next() {
	# $1=expr [$2=from epoch, default now] -> epoch of the next match at or
	# after the next minute boundary; fails when nothing matches within
	# ~366 days. Assumes a validated expression.
	local expr f1 f2 f3 f4 f5 t horizon y mo d h mi dow i
	local ny nmo mid prev from="${2:-}"
	expr="$(cron_expand "$1")"
	set -f
	# shellcheck disable=SC2086
	set -- $expr
	set +f
	[ $# -eq 5 ] || return 1
	f1="$1"
	f2="$2"
	f3="$3"
	f4="$4"
	f5="$5"
	if [ -n "$from" ]; then
		t="$from"
	else
		t=$(($(date +%s) / 60 * 60 + 60))
	fi
	horizon=$(($(date +%s) + 366 * 86400))
	i=0
	while [ "$t" -le "$horizon" ] && [ "$i" -lt 6000 ]; do
		i=$((i + 1))
		IFS=' ' read -r y mo d h mi dow <<<"$(ts_parts "$t")"
		mi=$((10#$mi))
		h=$((10#$h))
		d=$((10#$d))
		mo=$((10#$mo))
		dow=$((10#$dow))
		if ! cron_field_ok "$mo" "$f4" 1 12; then
			nmo=$((mo % 12 + 1))
			ny="$y"
			if [ "$nmo" -eq 1 ]; then ny=$((y + 1)); fi
			t="$(mktime_ymdhm "$ny" "$nmo" 1 0 0)" || return 1
			continue
		fi
		if ! cron_dom_dow_ok "$f3" "$(cron_norm_dow "$f5")" "$d" "$dow"; then
			mid="$(mktime_ymdhm "$y" "$mo" "$d" 0 0)" || return 1
			prev="$t"
			t=$((mid + 86400))
			while [ "$t" -le "$prev" ]; do t=$((t + 3600)); done
			IFS=' ' read -r y mo d h mi _dd <<<"$(ts_parts "$t")"
			if [ "$h" != "00" ] || [ "$mi" != "00" ]; then
				t="$(mktime_ymdhm "$y" "$mo" "$d" 0 0)" || return 1
			fi
			continue
		fi
		if ! cron_field_ok "$h" "$f2" 0 23; then
			t=$((t + 3600))
			IFS=' ' read -r y mo d h mi _dd <<<"$(ts_parts "$t")"
			t="$(mktime_ymdhm "$y" "$mo" "$d" "$h" 0)" || return 1
			continue
		fi
		if ! cron_field_ok "$mi" "$f1" 0 59; then
			t=$((t + 60))
			continue
		fi
		printf '%s' "$t"
		return 0
	done
	return 1
}

format_next() {
	# $1=epoch -> compact local display; the year shows only when not this year.
	local y now_y
	now_y="$(date +%Y)"
	y="$(date_fmt "$1" '%Y')"
	if [ "$y" = "$now_y" ]; then
		date_fmt "$1" '%b %d %H:%M'
	else
		date_fmt "$1" '%Y-%m-%d %H:%M'
	fi
}

next_run_for() {
	# $1=cron expr -> display string for the next occurrence, or an em dash.
	local next
	next="$(cron_next "$1" 2>/dev/null || true)"
	if [ -n "$next" ]; then
		format_next "$next"
	else
		printf '\u2014'
	fi
}

now_fields() {
	N_min=$((10#$(date +%M)))
	N_hour=$((10#$(date +%H)))
	N_dom=$((10#$(date +%d)))
	N_mon=$((10#$(date +%m)))
	N_dow=$((10#$(date +%w)))
	N_stamp="$(date +%Y%m%d%H%M)"
}

# --- locks (mkdir-based, macOS has no flock(1)) ------------------------------
# Lock dirs carry a `pid` file with the holder's pid. A crashed holder leaves
# a stale dir behind, so acquire steals the lock when the holder is dead.
# Watchers run in background subshells, hence ${BASHPID-$$} (BASHPID needs
# bash 4+; $$ is the parent's pid inside a subshell).
lock_acquire() {
	# $1=lockdir; returns 0 when acquired (or stolen from a dead holder),
	# 1 when held by a live process.
	local lock="$1" pid
	if mkdir "$lock" 2>/dev/null; then
		printf '%s' "${BASHPID-$$}" >"$lock/pid" 2>/dev/null || true
		return 0
	fi
	pid="$(cat "$lock/pid" 2>/dev/null || true)"
	case "$pid" in
	'' | *[!0-9]*) return 1 ;; # held, unknown holder — leave it alone
	esac
	if kill -0 "$pid" 2>/dev/null; then
		return 1
	fi
	rm -rf "$lock" 2>/dev/null || return 1
	if mkdir "$lock" 2>/dev/null; then
		printf '%s' "${BASHPID-$$}" >"$lock/pid" 2>/dev/null || true
		return 0
	fi
	return 1
}

lock_release() {
	rm -rf "$1" 2>/dev/null || true
}

daemon_lock() { printf '%s/daemon.lock' "$STATE_DIR"; }
run_lock() { printf '%s/running/%s.lock' "$STATE_DIR" "$1"; }
last_file() { printf '%s/last/%s' "$STATE_DIR" "$1"; }

daemon_alive() {
	local pid
	[ -f "$PID_FILE" ] || return 1
	pid="$(cat "$PID_FILE" 2>/dev/null)"
	case "$pid" in
	'' | *[!0-9]*) return 1 ;;
	esac
	kill -0 "$pid" 2>/dev/null
}

# --- firing ------------------------------------------------------------------
resolve_workspace_id() {
	# $1=label -> prints workspace_id or nothing (never fails: herdr may
	# be mid-restart when the daemon ticks).
	"$HERDR" workspace list 2>/dev/null |
		jq -r --arg l "$1" '.result.workspaces[] | select(.label == $l) | .workspace_id' 2>/dev/null |
		head -n1 || true
}

parse_string_list() {
	# Parse a single-line TOML string list like ["--verbose", '--model']
	# into the STRING_LIST array. Bare words are accepted leniently.
	# Returns 1 when malformed (no brackets, unterminated quote).
	STRING_LIST=()
	local s item="" q="" c i n
	case "$1" in
	\[*\]) ;;
	*) return 1 ;;
	esac
	s="$(printf '%s' "$1" | sed -e 's/^[[:space:]]*\[//' -e 's/\][[:space:]]*$//')"
	if [ -z "$(printf '%s' "$s" | tr -d '[:space:],')" ]; then
		return 0
	fi
	n=${#s}
	i=0
	while [ "$i" -lt "$n" ]; do
		c="${s:i:1}"
		if [ -n "$q" ]; then
			if [ "$c" = "$q" ]; then
				q=""
			else
				item="$item$c"
			fi
		else
			case "$c" in
			'"' | "'") q="$c" ;;
			,)
				STRING_LIST[${#STRING_LIST[@]}]="$item"
				item=""
				;;
			'' | *[[:space:]]*) ;;
			*) item="$item$c" ;;
			esac
		fi
		i=$((i + 1))
	done
	if [ -n "$q" ]; then
		return 1
	fi
	if [ -n "$item" ]; then
		STRING_LIST[${#STRING_LIST[@]}]="$item"
	fi
	return 0
}

agent_state() {
	# $1=pane_id -> prints working|blocked|done|idle|unknown; returns 1 when
	# the pane/agent is gone (or herdr is unreachable).
	local state
	state="$("$HERDR" agent get "$1" 2>/dev/null | jq -r '.result.agent.agent_status // empty' 2>/dev/null || true)"
	[ -n "$state" ] || return 1
	printf '%s' "$state"
}

update_last_status() {
	# $1=name $2=status: rewrite the last-file status, keeping the occurrence
	# stamp (so the same-minute dedup keeps holding).
	local lf stamp trigger ws pane
	lf="$(last_file "$1")"
	[ -f "$lf" ] || return 0
	IFS=$'\t' read -r stamp trigger _ ws pane <"$lf" || true
	[ -n "$stamp" ] || return 0
	printf '%s\t%s\t%s\t%s\t%s\n' "$stamp" "$trigger" "$2" "$ws" "$pane" >"$lf"
}

lock_held() {
	# $1=lockdir; 0 when held by a live process (unknown holder counts as held).
	local pid
	[ -d "$1" ] || return 1
	pid="$(cat "$1/pid" 2>/dev/null || true)"
	case "$pid" in
	'' | *[!0-9]*) return 0 ;;
	esac
	kill -0 "$pid" 2>/dev/null
}

retry_file() { printf '%s/retry/%s' "$STATE_DIR" "$1"; }

record_retry() {
	# $1=name: record a pre-start failure; prints the attempt count.
	local rf n="" first="" now
	rf="$(retry_file "$1")"
	now="$(date +%s)"
	mkdir -p "$STATE_DIR/retry"
	if [ -f "$rf" ]; then
		IFS=$'\t' read -r n first <"$rf" 2>/dev/null || true
	fi
	case "$n" in '' | *[!0-9]*) n=0 ;; esac
	[ -n "$first" ] || first="$now"
	n=$((n + 1))
	printf '%s\t%s\n' "$n" "$first" >"$rf"
	printf '%s' "$n"
}

retry_due() {
	# $1=name: 0 when a failed launch is owed a retry (attempts < 3 and the
	# first failure is under 10 minutes old; older chains expire silently).
	local rf n first now
	rf="$(retry_file "$1")"
	[ -f "$rf" ] || return 1
	IFS=$'\t' read -r n first <"$rf" 2>/dev/null || return 1
	case "$n" in '' | *[!0-9]*) return 1 ;; esac
	case "$first" in '' | *[!0-9]*) return 1 ;; esac
	[ "$n" -lt 3 ] || return 1
	now="$(date +%s)"
	if [ "$((now - first))" -ge 600 ]; then
		rm -f "$rf"
		return 1
	fi
	return 0
}

clear_retry() { rm -f "$(retry_file "$1")"; }

fail_run() {
	# $1=name $2=trigger $3=lock $4=detail $5=notify-text — pre-start failure
	# path: schedule failures ride the retry chain (notify on give-up),
	# manual failures notify immediately. Releases the lock. Always returns 1.
	local name="$1" trigger="$2" lock="$3" detail="$4" note="$5" attempts
	if [ "$trigger" = "schedule" ]; then
		attempts="$(record_retry "$name")"
		log_msg "$name	run	$trigger	error	$detail (attempt $attempts/3)"
		if [ "$attempts" -ge 3 ]; then
			notify "Automation failed: $name" "$note — giving up after 3 attempts."
			clear_retry "$name"
		fi
	else
		log_msg "$name	run	$trigger	error	$detail"
		notify "Automation failed: $name" "$note"
	fi
	lock_release "$lock"
	return 1
}

watch_run() {
	# $1=name $2=ws_id $3=pane_id $4=trigger $5=stamp $6=watch_secs
	# $7=auto_close $8=description — launched backgrounded (&) after a
	# successful prompt: owns the run lock until it returns (trap releases
	# it), polls the agent state, and records the terminal outcome.
	local name="$1" ws_id="$2" pane_id="$3" trigger="$4" stamp="$5"
	local watch_secs="$6" auto_close="$7" desc="$8"
	local lock deadline state fails=0 notified=false body
	lock="$(run_lock "$name")"
	trap 'lock_release "$lock"' EXIT
	deadline=$(($(date +%s) + watch_secs))
	while :; do
		if state="$(agent_state "$pane_id")"; then
			fails=0
			case "$state" in
			done)
				update_last_status "$name" completed
				log_msg "$name	run	$trigger	completed	workspace=$ws_id pane=$pane_id"
				if [ "$auto_close" = "true" ]; then
					"$HERDR" workspace close "$ws_id" >/dev/null 2>&1 || true
				fi
				return 0
				;;
			blocked)
				if [ "$notified" = false ]; then
					notified=true
					body="needs input in $ws_id"
					[ -n "$desc" ] && body="$desc — $body"
					notify "Automation blocked: $name" "$body"
					log_msg "$name	run	$trigger	blocked	workspace=$ws_id pane=$pane_id"
				fi
				;;
			working | idle | unknown) ;;
			*)
				update_last_status "$name" attention
				log_msg "$name	run	$trigger	attention	unexpected state: $state"
				return 0
				;;
			esac
		else
			fails=$((fails + 1))
			if [ "$fails" -ge 2 ]; then
				update_last_status "$name" cancelled
				log_msg "$name	run	$trigger	cancelled	pane $pane_id gone"
				return 0
			fi
		fi
		if [ "$(date +%s)" -ge "$deadline" ]; then
			update_last_status "$name" attention
			log_msg "$name	run	$trigger	attention	watch window exceeded"
			return 0
		fi
		sleep "${AUTOMATIONS_POLL_SECS:-30}"
	done
}

fire_automation() {
	# $1=file $2=block $3=trigger(schedule|manual)
	local file="$1" block="$2" trigger="$3" lock ws_id dir pane pane_id rest pane_agent pane_status notify_body
	local passthru aa
	parse_entry "$file" "$block"
	if [ -n "$A_error" ]; then
		log_msg "$A_name	run	$trigger	error	$A_error"
		notify "Automation failed: $(basename "$file")" "$A_error"
		return 1
	fi
	if [ "$A_enabled" != "true" ] && [ "$trigger" = "schedule" ]; then
		return 0
	fi
	lock="$(run_lock "$A_name")"
	if ! lock_acquire "$lock"; then
		log_msg "$A_name	run	$trigger	skipped	previous run still active"
		return 0
	fi
	# lock held for the launch; background the slow herdr calls is overkill —
	# launching is seconds, and the lock serialises schedule vs manual.
	{
		dir="${A_directory:-$HOME}"
		case "$dir" in
		\~/*) dir="$HOME/${dir#\~/}" ;;
		\~) dir="$HOME" ;;
		esac
		ws_id="$(resolve_workspace_id "$A_workspace")"
		if [ -z "$ws_id" ]; then
			ws_id="$("$HERDR" workspace create --cwd "$dir" --label "$A_workspace" --no-focus 2>/dev/null |
				jq -r '.result.workspace_id // .result.workspaces[0].workspace_id // empty' || true)"
			[ -z "$ws_id" ] && ws_id="$(resolve_workspace_id "$A_workspace")"
		fi
		if [ -z "$ws_id" ]; then
			fail_run "$A_name" "$trigger" "$lock" \
				"cannot resolve or create workspace $A_workspace" \
				"Cannot resolve or create workspace '$A_workspace'."
			return 1
		fi
		pane="$("$HERDR" pane list --workspace "$ws_id" 2>/dev/null |
			jq -r --arg a "$A_agent" '
          (.result.panes // []) as $p
          | (($p | map(select(.agent == $a)) | first) // ($p | first) // empty)
          | [.pane_id, (.agent // ""), (.agent_status // "")] | @tsv' || true)"
		pane_id="${pane%%$'\t'*}"
		rest="${pane#*$'\t'}"
		pane_agent="${rest%%$'\t'*}"
		pane_status="${rest##*$'\t'}"
		if [ -z "$pane_id" ]; then
			fail_run "$A_name" "$trigger" "$lock" \
				"no panes in workspace $A_workspace" \
				"No panes in workspace '$A_workspace'."
			return 1
		fi
		if [ "$pane_agent" != "$A_agent" ] || [ "$pane_status" = "unknown" ]; then
			passthru=()
			if [ -n "$A_model" ]; then
				passthru[${#passthru[@]}]="--model"
				passthru[${#passthru[@]}]="$A_model"
			fi
			if [ -n "$A_agent_args" ]; then
				if ! parse_string_list "$A_agent_args"; then
					fail_run "$A_name" "$trigger" "$lock" "bad agent_args" "Bad agent_args list."
					return 1
				fi
				for aa in ${STRING_LIST[@]+"${STRING_LIST[@]}"}; do
					passthru[${#passthru[@]}]="$aa"
				done
			fi
			if [ "${#passthru[@]}" -gt 0 ]; then
				"$HERDR" agent start "$A_name" --kind "$A_agent" --pane "$pane_id" -- "${passthru[@]}" >/dev/null 2>&1 || true
			else
				"$HERDR" agent start "$A_name" --kind "$A_agent" --pane "$pane_id" >/dev/null 2>&1 || true
			fi
		fi
		if "$HERDR" agent prompt "$pane_id" "$A_command" >/dev/null 2>&1; then
			now_fields
			mkdir -p "$STATE_DIR/last"
			if [ "$trigger" = "schedule" ]; then
				printf '%s\t%s\trunning\t%s\t%s\n' "$N_stamp" "$trigger" "$ws_id" "$pane_id" >"$(last_file "$A_name")"
			else
				printf '%s\t%s\tstarted\t%s\t%s\n' "$N_stamp" "$trigger" "$ws_id" "$pane_id" >"$(last_file "$A_name")"
			fi
			clear_retry "$A_name"
			log_msg "$A_name	run	$trigger	started	workspace=$A_workspace pane=$pane_id"
			notify_body="$A_workspace / $A_agent ($trigger)"
			if [ -n "$A_description" ]; then
				notify_body="$A_description — $notify_body"
			fi
			notify "Automation fired: $A_name" "$notify_body"
			if [ "$trigger" = "schedule" ]; then
				# Hand the run lock to the background watcher, which
				# releases it when the run reaches a terminal state.
				watch_run "$A_name" "$ws_id" "$pane_id" "$trigger" "$N_stamp" \
					"$((A_watch_minutes * 60))" "$A_auto_close" "$A_description" &
			else
				lock_release "$lock"
			fi
		else
			fail_run "$A_name" "$trigger" "$lock" \
				"agent prompt failed" "Agent prompt failed in '$A_workspace'."
			return 1
		fi
	}
}

# --- entry sources -----------------------------------------------------------
# Automations live in repo files (<repo>/.herdr-automations.toml, one
# [[automation]] block each) plus the legacy global dir (<config>/automations/
# *.toml, one flat automation per file). Names must be unique across ALL
# sources: runtime state (locks, last-run, retries) is keyed by name, so a
# duplicate disables every entry carrying it until renamed.
REPO_FILENAME=".herdr-automations.toml"

registry_file() { printf '%s/repos' "$CONFIG_DIR"; }

register_repo() {
	# $1=repo path: append to the registry unless already present.
	local reg line
	reg="$(registry_file)"
	mkdir -p "$CONFIG_DIR"
	touch "$reg"
	while IFS= read -r line; do
		[ "$line" = "$1" ] && return 0
	done <"$reg"
	printf '%s\n' "$1" >>"$reg"
}

raw_entries() {
	# Prints file<TAB>block<TAB>label for every entry, without parsing:
	# registered repos first, then the global fallback dir. Block 0 means
	# "whole flat file"; otherwise a 1-based [[automation]] index.
	local repo repofile count i f
	if [ -f "$(registry_file)" ]; then
		while IFS= read -r repo; do
			case "$repo" in '' | \#*) continue ;; esac
			repofile="$repo/$REPO_FILENAME"
			[ -f "$repofile" ] || continue
			count="$(grep -c '^\[\[automation\]\]' "$repofile" 2>/dev/null || true)"
			case "$count" in '' | *[!0-9]*) count=0 ;; esac
			if [ "$count" -eq 0 ]; then
				printf '%s\t0\t%s\n' "$repofile" "$repo"
			else
				i=0
				while [ "$i" -lt "$count" ]; do
					i=$((i + 1))
					printf '%s\t%s\t%s\n' "$repofile" "$i" "$repo"
				done
			fi
		done <"$(registry_file)"
	fi
	for f in "$ACTIONS_DIR"/*.toml; do
		[ -f "$f" ] || continue
		printf '%s\t0\tglobal\n' "$f"
	done
}

list_entries() {
	# Prints file<TAB>block<TAB>label<TAB>name for every entry. Parse errors
	# yield ERR:<name-or-empty>; names used by more than one entry yield
	# DUP:<name> (callers must never fire error or duplicate rows).
	local efiles=() eblocks=() elabels=() enames=() onames=()
	local file block label name i j n dup
	while IFS=$'\t' read -r file block label; do
		[ -n "$file" ] || continue
		efiles[${#efiles[@]}]="$file"
		eblocks[${#eblocks[@]}]="$block"
		elabels[${#elabels[@]}]="$label"
		parse_entry "$file" "$block"
		if [ -n "$A_error" ]; then
			enames[${#enames[@]}]="ERR:$A_name"
		else
			enames[${#enames[@]}]="$A_name"
		fi
		onames[${#onames[@]}]="${enames[$((${#enames[@]} - 1))]}"
	done < <(raw_entries)
	n=${#efiles[@]}
	i=0
	while [ "$i" -lt "$n" ]; do
		name="${enames[i]}"
		if [ -n "$name" ]; then
			dup=0
			j=0
			while [ "$j" -lt "$n" ]; do
				if [ "$j" -ne "$i" ] && [ "${onames[j]}" = "$name" ]; then
					dup=1
					break
				fi
				j=$((j + 1))
			done
			if [ "$dup" -eq 1 ]; then
				enames[i]="DUP:$name"
			fi
		fi
		i=$((i + 1))
	done
	i=0
	while [ "$i" -lt "$n" ]; do
		printf '%s\t%s\t%s\t%s\n' "${efiles[i]}" "${eblocks[i]}" "${elabels[i]}" "${enames[i]}"
		i=$((i + 1))
	done
}

find_entry() {
	# $1=name: prints file<TAB>block<TAB>label for the entry, or fails
	# (missing or duplicated) with a message on stderr. Broken entries
	# resolve too, so show/run/open/enable can report their parse error.
	local file block label ename errfile="" errblock="" errlabel=""
	while IFS=$'\t' read -r file block label ename; do
		[ -n "$file" ] || continue
		if [ "$ename" = "DUP:$1" ]; then
			printf 'duplicate automation name: %s\n' "$1" >&2
			return 1
		fi
		if [ "$ename" = "$1" ]; then
			printf '%s\t%s\t%s\n' "$file" "$block" "$label"
			return 0
		fi
		if [ -z "$errfile" ] && [ "$ename" = "ERR:$1" ]; then
			errfile="$file"
			errblock="$block"
			errlabel="$label"
		fi
	done < <(list_entries)
	if [ -n "$errfile" ]; then
		printf '%s\t%s\t%s\n' "$errfile" "$errblock" "$errlabel"
		return 0
	fi
	printf 'no automation named %s\n' "$1" >&2
	return 1
}

set_entry_key() {
	# $1=file $2=block $3=key $4=value: rewrite the key inside one entry,
	# appending it at the block end when absent. Prints the new file content.
	local file="$1" blk="$2" skey="$3" sval="$4"
	awk -v blk="$blk" -v key="$skey" -v val="$sval" '
	BEGIN { inb = (blk == 0) }
	/^\[\[automation\]\]/ && blk != 0 {
		if (inb && !done) { print key" = "val; done = 1 }
		n++; inb = (n == blk)
		print; next
	}
	{
		if (inb && !done && $0 ~ "^"key"[ \t]*=") { print key" = "val; done = 1; next }
		print
	}
	END { if (inb && !done) print key" = "val }
	' "$file"
}

write_flat() {
	# $1=file: write a flat single-automation file from the A_* globals
	# (legacy global format). Returns 1 on an unquotable value.
	local key val q
	for key in name description cron workspace agent model auto_close command directory; do
		case "$key" in
		name) val="$A_name" ;;
		description) val="$A_description" ;;
		cron) val="$A_cron" ;;
		workspace) val="$A_workspace" ;;
		agent) val="$A_agent" ;;
		model) val="$A_model" ;;
		auto_close) val="$A_auto_close" ;;
		command) val="$A_command" ;;
		directory) val="$A_directory" ;;
		esac
		if [ -z "$val" ]; then
			case "$key" in description | model | directory) continue ;; esac
		fi
		if ! q="$(toml_quote "$val")"; then
			printf 'Cannot quote the %s value (mixed quotes) — please rephrase.\n' "$key" >/dev/tty
			return 1
		fi
		printf '%s = %s\n' "$key" "$q" >>"$1"
	done
	printf 'enabled = %s\n' "$A_enabled" >>"$1"
}

append_block() {
	# $1=file: append one [[automation]] block from the A_* globals.
	# Returns 1 on an unquotable value.
	local key val q
	printf '\n[[automation]]\n' >>"$1"
	for key in name description cron workspace agent model auto_close command directory enabled; do
		case "$key" in
		name) val="$A_name" ;;
		description) val="$A_description" ;;
		cron) val="$A_cron" ;;
		workspace) val="$A_workspace" ;;
		agent) val="$A_agent" ;;
		model) val="$A_model" ;;
		auto_close) val="$A_auto_close" ;;
		command) val="$A_command" ;;
		directory) val="$A_directory" ;;
		enabled) val="$A_enabled" ;;
		esac
		if [ -z "$val" ]; then
			case "$key" in description | model | directory) continue ;; esac
		fi
		if ! q="$(toml_quote "$val")"; then
			printf 'Cannot quote the %s value (mixed quotes) — please rephrase.\n' "$key" >/dev/tty
			return 1
		fi
		printf '%s = %s\n' "$key" "$q" >>"$1"
	done
}

migrate_globals() {
	# $1=repo file (already created): import valid global flat files as
	# blocks and move them aside. Example files stay put. Prints moved/skipped.
	local f moved=0 skipped=0
	for f in "$ACTIONS_DIR"/*.toml; do
		[ -f "$f" ] || continue
		case "$(basename "$f")" in example-*)
			skipped=$((skipped + 1))
			continue
			;;
		esac
		parse_entry "$f" 0
		if [ -n "$A_error" ]; then
			skipped=$((skipped + 1))
			continue
		fi
		append_block "$1" || {
			skipped=$((skipped + 1))
			continue
		}
		rm -f "$f"
		moved=$((moved + 1))
	done
	printf '%d migrated, %d left behind\n' "$moved" "$skipped"
}

# --- daemon --------------------------------------------------------------------
tick_once() {
	local file block label ename stamp
	now_fields
	stamp="$N_stamp"
	mkdir -p "$STATE_DIR/last" "$STATE_DIR/running"
	while IFS=$'\t' read -r file block label ename; do
		[ -n "$file" ] || continue
		case "$ename" in
		ERR:*)
			parse_entry "$file" "$block"
			log_msg "$(entry_tag "$file" "$block" "$label")	tick	error	$A_error"
			continue
			;;
		DUP:*)
			log_msg "${ename#DUP:}	tick	error	duplicate name (also in another source)"
			continue
			;;
		esac
		parse_entry "$file" "$block"
		if [ -n "$A_error" ]; then
			log_msg "$(entry_tag "$file" "$block" "$label")	tick	error	$A_error"
			continue
		fi
		[ "$A_enabled" = "true" ] || continue
		if cron_match "$A_cron" "$N_min" "$N_hour" "$N_dom" "$N_mon" "$N_dow"; then
			if [ -f "$(last_file "$A_name")" ] && grep -q "^$stamp" "$(last_file "$A_name")" 2>/dev/null; then
				continue # already fired this minute
			fi
			clear_retry "$A_name" # new occurrence supersedes any retry chain
			fire_automation "$file" "$block" schedule || true
		elif retry_due "$A_name"; then
			fire_automation "$file" "$block" schedule || true
		fi
	done < <(list_entries)
}

cmd_daemon() {
	local detach=false
	[ "${1:-}" = "--detach" ] && detach=true
	if [ "$detach" = true ]; then
		if daemon_alive; then
			printf 'automation daemon already running (pid %s)\n' "$(cat "$PID_FILE")"
			return 0
		fi
		mkdir -p "$STATE_DIR"
		# needs the socket env herdr injects into its panes
		nohup bash "$SCRIPT" daemon >>"$LOG_FILE" 2>&1 &
		printf '%s' "$!" >"$PID_FILE"
		printf 'automation daemon spawned (pid %s), log: %s\n' "$!" "$LOG_FILE"
		return 0
	fi
	if ! lock_acquire "$(daemon_lock)"; then
		printf 'another automation daemon holds the lock; exiting\n' >&2
		exit 1
	fi
	trap 'lock_release "$(daemon_lock)"; rm -f "$PID_FILE"; exit 0' INT TERM EXIT
	printf '%s' "$$" >"$PID_FILE"
	mkdir -p "$ACTIONS_DIR"
	seed_example || true
	if [ -z "${HERDR_SOCKET_PATH:-}" ] && ! "$HERDR" status >/dev/null 2>&1; then
		printf 'HERDR_SOCKET_PATH is not set and herdr is unreachable; start the daemon from inside herdr\n' >&2
		exit 1
	fi
	log_msg "daemon	start	pid=$$"
	while :; do
		tick_once
		sleep $((60 - 10#$(date +%S)))
	done
}

seed_example() {
	# First start seeds one disabled example; never rewritten once the dir exists.
	if [ ! -d "$ACTIONS_DIR" ] || [ -z "$(ls -A "$ACTIONS_DIR" 2>/dev/null)" ]; then
		mkdir -p "$ACTIONS_DIR"
		cp -f "$SCRIPT_DIR/example-cron.toml" "$ACTIONS_DIR/example-cron.toml"
		log_msg "daemon	seed	wrote example-cron.toml (enabled = false)"
	fi
}

# --- display ---------------------------------------------------------------------
last_info() {
	# $1=name -> "<stamp> <trigger> <status>" or "never" (run-record
	# fields beyond the third, e.g. workspace/pane ids, are not shown).
	local lf
	lf="$(last_file "$1")"
	if [ -f "$lf" ]; then
		cut -f1-3 <"$lf" | tr '\t' ' '
	else
		printf 'never'
	fi
}

last_workspace() {
	# $1=name -> workspace_id of the last run, or nothing (pre-descriptions
	# records with only three fields simply yield empty).
	local lf
	lf="$(last_file "$1")"
	[ -f "$lf" ] || return 1
	cut -f4 <"$lf"
}

entry_tag() {
	# $1=file $2=block $3=label: short display tag for broken entries.
	if [ "$3" = "global" ]; then
		basename "$1" .toml
	else
		printf '%s#%s' "$(basename "$3")" "$2"
	fi
}

repo_short() {
	# $1=label: repo basename, or "global" for the fallback dir.
	if [ "$1" = "global" ]; then
		printf 'global'
	else
		basename "$1"
	fi
}

cmd_list() {
	local file block label ename next sub
	printf '%-22s %-16s %-7s %-26s %-16s %s\n' "NAME" "SCHEDULE" "ENABLED" "LAST RUN" "NEXT RUN" "REPO"
	while IFS=$'\t' read -r file block label ename; do
		[ -n "$file" ] || continue
		case "$ename" in
		ERR:*)
			parse_entry "$file" "$block"
			printf '%-22s %-16s %-7s %-26s %-16s %s\n' "$(entry_tag "$file" "$block" "$label")" "error" "-" "-" "-" "$(repo_short "$label")"
			printf '  # %s\n' "$A_error"
			continue
			;;
		DUP:*)
			printf '%-22s %-16s %-7s %-26s %-16s %s\n' "${ename#DUP:}" "error" "-" "-" "-" "$(repo_short "$label")"
			printf '  # duplicate name (also in another source)\n'
			continue
			;;
		esac
		parse_entry "$file" "$block"
		if [ -n "$A_error" ]; then
			printf '%-22s %-16s %-7s %-26s %-16s %s\n' "$(entry_tag "$file" "$block" "$label")" "error" "-" "-" "-" "$(repo_short "$label")"
			continue
		fi
		next="$(next_run_for "$A_cron")"
		sub="$A_workspace / $A_agent"
		if [ -n "$A_model" ]; then
			sub="$A_workspace / $A_agent ($A_model)"
		fi
		if [ -n "$A_description" ]; then
			sub="$A_description — $sub"
		fi
		printf '%-22s %-16s %-7s %-26s %-16s %s\n' "$A_name" "$A_cron" "$A_enabled" "$(last_info "$A_name")" "$next" "$(repo_short "$label")"
		printf '  # %s\n' "$sub"
	done < <(list_entries)
}

cmd_status() {
	local total=0 enabled=0 errors=0 file block label ename
	while IFS=$'\t' read -r file block label ename; do
		[ -n "$file" ] || continue
		total=$((total + 1))
		case "$ename" in
		ERR:* | DUP:*)
			errors=$((errors + 1))
			;;
		*)
			parse_entry "$file" "$block"
			if [ -n "$A_error" ]; then
				errors=$((errors + 1))
			elif [ "$A_enabled" = "true" ]; then
				enabled=$((enabled + 1))
			fi
			;;
		esac
	done < <(list_entries)
	if daemon_alive; then
		printf 'Automation daemon running (pid %s)\n' "$(cat "$PID_FILE")"
	else
		printf 'Automation daemon not running (start it from inside herdr: automations.sh daemon --detach)\n'
	fi
	printf '%d automation(s): %d enabled, %d with errors\n' "$total" "$enabled" "$errors"
	cmd_list
}

cmd_rows() {
	# Picker rows: <idx>\t<run>\t<label>\t<badge>. Selecting an automation
	# opens its details view (run/enable/open live inside it); the leading
	# "+ new" row opens the creation wizard instead. Both carry
	# close_on_exit=false so the popup survives the interaction.
	local file block label ename i=0 rowlabel badge last agent_label
	printf '0\t"%s" board\t+ board (live table)\tboard\tfalse\n' "$SCRIPT"
	i=$((i + 1))
	printf '%d\t"%s" new\t+ new automation\u2026\tnew\tfalse\n' "$i" "$SCRIPT"
	while IFS=$'\t' read -r file block label ename; do
		[ -n "$file" ] || continue
		i=$((i + 1))
		case "$ename" in
		ERR:*)
			parse_entry "$file" "$block"
			rowlabel="$(entry_tag "$file" "$block" "$label") — $A_error"
			printf '%d\t:\t%s\terror\n' "$i" "$rowlabel"
			continue
			;;
		DUP:*)
			rowlabel="${ename#DUP:} — duplicate name (also in another source)"
			printf '%d\t:\t%s\terror\n' "$i" "$rowlabel"
			continue
			;;
		esac
		parse_entry "$file" "$block"
		if [ -n "$A_error" ]; then
			rowlabel="$(entry_tag "$file" "$block" "$label") — $A_error"
			printf '%d\t:\t%s\terror\n' "$i" "$rowlabel"
			continue
		fi
		last="$(last_info "$A_name")"
		agent_label="$A_agent"
		if [ -n "$A_model" ]; then
			agent_label="$A_agent ($A_model)"
		fi
		rowlabel="$A_name — $A_cron — $A_workspace / $agent_label — last: $last"
		if [ -n "$A_description" ]; then
			rowlabel="$A_name — $A_description — $A_cron — $A_workspace / $agent_label — last: $last"
		fi
		if lock_held "$(run_lock "$A_name")"; then
			badge="running"
		elif [ "$A_enabled" = "true" ]; then
			badge="enabled"
		else
			badge="disabled"
		fi
		printf '%d\t"%s" show "%s"\t%s\t%s\tfalse\n' "$i" "$SCRIPT" "$A_name" "$rowlabel" "$badge"
	done < <(list_entries)
}

# --- creation wizard -----------------------------------------------------------
# Guided form for new automations (the picker's "+ new" row, or
# `automations.sh new`). Mirrors shepherd's board form: per-field help,
# schedule presets, validation with the same parser the daemon uses before
# anything is written, and new automations start enabled (enabled = true).
#
# All interaction goes to /dev/tty: in the picker popup stdin is the pane's
# tty, and the rows entry carries close_on_exit=false so the summary stays
# visible until Enter.
wizard_read() {
	# $1=prompt $2=default (optional) -> sets WIZ_VAL; returns 1 on EOF.
	local prompt="$1" def="${2:-}" line
	if [ -n "$def" ]; then
		printf '%s [%s]: ' "$prompt" "$def" >/dev/tty
	else
		printf '%s: ' "$prompt" >/dev/tty
	fi
	IFS= read -r line </dev/tty || {
		printf '\nAborted.\n' >/dev/tty
		return 1
	}
	if [ -z "$line" ]; then
		line="$def"
	fi
	WIZ_VAL="$line"
}

wizard_number() {
	# $1=prompt $2=min $3=max $4=default -> sets WIZ_VAL; re-prompts.
	local prompt="$1" min="$2" max="$3" def="$4" line
	while :; do
		wizard_read "$prompt" "$def" || return 1
		line="$WIZ_VAL"
		case "$line" in
		'' | *[!0-9]*)
			printf 'Enter a number %s-%s.\n' "$min" "$max" >/dev/tty
			continue
			;;
		esac
		if [ "$line" -ge "$min" ] && [ "$line" -le "$max" ]; then
			WIZ_VAL="$line"
			return 0
		fi
		printf 'Enter a number %s-%s.\n' "$min" "$max" >/dev/tty
	done
}

wizard_confirm() {
	# $1=prompt -> returns 0 on yes, 1 on no; anything else re-prompts
	# (so stray pasted lines can never accidentally confirm).
	local prompt="$1"
	while :; do
		wizard_read "$prompt [y/n]" "y" || return 1
		case "$WIZ_VAL" in
		[yY] | [yY][eE][sS]) return 0 ;;
		[nN] | [nN][oO]) return 1 ;;
		esac
	done
}

valid_name() {
	# automation names become lock/last filenames: no whitespace, /, \, or leading dot.
	case "$1" in
	"" | *[[:space:]/\\]* | .*) return 1 ;;
	esac
	return 0
}

toml_quote() {
	# Quote a value for TOML output. Prefers basic strings; falls back to
	# literal strings when the value holds double quotes; fails when it holds
	# both quote types (vanishingly rare — the wizard asks to rephrase).
	local v="$1"
	case "$v" in
	*\"*)
		case "$v" in
		*"'"*) return 1 ;;
		*) printf "'%s'" "$v" ;;
		esac
		;;
	*) printf '"%s"' "$v" ;;
	esac
}

cmd_new() {
	local name="" cron="" workspace="" agent="" command="" directory="" description=""
	local model="" auto_close="false"
	local labels label_count choice tmp q line i a
	local -a known=(pi claude codex gemini opencode)
	if ! exec 3</dev/tty 2>/dev/null; then
		printf 'automations.sh new needs an interactive terminal\n' >&2
		return 1
	fi
	exec 3<&-
	mkdir -p "$ACTIONS_DIR" "$STATE_DIR"
	printf 'New automation (starts enabled: enabled = true).\n\n' >/dev/tty

	# Target: the enclosing repo's file, or the global dir outside a repo.
	local wiz_base wiz_root wiz_repofile wiz_fresh ef _eb el en dup_label mig
	wiz_base="${HERDR_LAUNCHER_CWD:-$PWD}"
	wiz_root="$(git -C "$wiz_base" rev-parse --show-toplevel 2>/dev/null || true)"
	wiz_repofile=""
	if [ -n "$wiz_root" ]; then
		wiz_repofile="$wiz_root/$REPO_FILENAME"
	fi

	# 1. name: unique across ALL sources (runtime state is keyed by name)
	# and filename-safe.
	while :; do
		wizard_read "Name (letters, digits, dashes)" || return 1
		name="$WIZ_VAL"
		if ! valid_name "$name"; then
			printf 'Bad name: no spaces, slashes, or leading dots.\n' >/dev/tty
			continue
		fi
		dup_label=""
		while IFS=$'\t' read -r ef _eb el en; do
			[ -n "$ef" ] || continue
			if [ "$en" = "$name" ] || [ "$en" = "DUP:$name" ] || [ "$en" = "ERR:$name" ]; then
				dup_label="$el"
				break
			fi
		done < <(list_entries)
		if [ -n "$dup_label" ]; then
			printf 'Name %s is already used (%s).\n' "$name" "$dup_label" >/dev/tty
			continue
		fi
		break
	done

	# 1b. description (optional free text shown in listings and the picker).
	wizard_read "Description (optional)" || return 1
	description="$WIZ_VAL"

	# 2. schedule preset -> cron (custom expressions use the daemon's validator).
	printf '\nSchedule:\n  1) hourly\n  2) daily\n  3) weekdays (Mon-Fri)\n  4) custom cron expression\n' >/dev/tty
	wizard_number "Preset" 1 4 2 || return 1
	case "$WIZ_VAL" in
	1)
		wizard_number "Minute (0-59)" 0 59 0 || return 1
		cron="$WIZ_VAL * * * *"
		;;
	2 | 3)
		choice="$WIZ_VAL"
		wizard_number "Hour (0-23)" 0 23 9 || return 1
		line="$WIZ_VAL"
		wizard_number "Minute (0-59)" 0 59 0 || return 1
		if [ "$choice" = "3" ]; then
			cron="$WIZ_VAL $line * * 1-5"
		else
			cron="$WIZ_VAL $line * * *"
		fi
		;;
	4)
		printf 'Five fields: minute hour day-of-month month day-of-week (e.g. 15 6 * * 1-5).\n' >/dev/tty
		while :; do
			wizard_read "Cron expression" || return 1
			A_cron="$WIZ_VAL"
			A_error=""
			if validate_cron "$A_cron"; then
				cron="$A_cron"
				break
			fi
			printf 'Invalid: %s\n' "$A_error" >/dev/tty
		done
		;;
	esac

	# 3. workspace: pick an existing one or name a new one (created on first run).
	printf '\nWorkspace — the run opens here.\n' >/dev/tty
	labels="$("$HERDR" workspace list 2>/dev/null | jq -r '.result.workspaces[].label' 2>/dev/null || true)"
	label_count=0
	if [ -n "$labels" ]; then
		i=0
		while IFS= read -r line; do
			i=$((i + 1))
			printf '  %d) %s\n' "$i" "$line" >/dev/tty
		done <<<"$labels"
		label_count="$i"
	fi
	while :; do
		if [ "$label_count" -gt 0 ]; then
			wizard_read "Pick a number, or type a new label" || return 1
		else
			wizard_read "Workspace label" || return 1
		fi
		choice="$WIZ_VAL"
		case "$choice" in
		'' | *[!0-9]*)
			workspace="$choice"
			;;
		*)
			if [ "$choice" -ge 1 ] && [ "$choice" -le "$label_count" ]; then
				workspace="$(printf '%s\n' "$labels" | sed -n "${choice}p")"
			else
				workspace="$choice"
			fi
			;;
		esac
		if [ -n "$workspace" ]; then
			break
		fi
		printf 'Workspace cannot be empty.\n' >/dev/tty
	done
	if ! printf '%s\n' "$labels" | grep -qxF "$workspace"; then
		printf "Note: '%s' does not exist yet — it will be created on first run.\n" "$workspace" >/dev/tty
	fi

	# 4. agent kind.
	printf '\nAgent:\n' >/dev/tty
	i=0
	for a in "${known[@]}"; do
		i=$((i + 1))
		printf '  %d) %s\n' "$i" "$a" >/dev/tty
	done
	wizard_read "Pick a number, or type an agent kind" "claude" || return 1
	choice="$WIZ_VAL"
	case "$choice" in
	*[!0-9]* | "")
		agent="$choice"
		;;
	*)
		if [ "$choice" -ge 1 ] && [ "$choice" -le "${#known[@]}" ]; then
			agent="${known[$((choice - 1))]}"
		else
			agent="$choice"
		fi
		;;
	esac
	if [ -z "$agent" ]; then
		printf 'Agent cannot be empty.\n' >/dev/tty
		return 1
	fi

	# 4b. model (optional; kinds accepting --model are checked at load).
	wizard_read "Model (optional, passed as --model)" || return 1
	model="$WIZ_VAL"

	# 4c. auto-close (optional; closes the workspace when the run ends).
	# Non-yes answers fall through to false — the safe direction.
	wizard_read "Close workspace when the run finishes [y/n]" "n" || return 1
	case "$WIZ_VAL" in
	[yY] | [yY][eE][sS]) auto_close="true" ;;
	*) auto_close="false" ;;
	esac

	# 5. command (single line; the strict confirm loop below also guards
	# against stray lines from a multiline paste).
	while :; do
		wizard_read "Command (prompt sent to the agent)" || return 1
		command="$WIZ_VAL"
		if [ -n "$command" ]; then
			break
		fi
		printf 'Command cannot be empty.\n' >/dev/tty
	done

	# 6. working directory (supports ~; used when creating the workspace).
	wizard_read "Directory" "$PWD" || return 1
	directory="$WIZ_VAL"
	if [ -z "$directory" ]; then
		directory="$PWD"
	fi

	# 7. summary, then validate-with-the-daemon-parser before writing.
	printf '\n---\n' >/dev/tty
	printf 'name:      %s\n' "$name" >/dev/tty
	printf 'description: %s\n' "$description" >/dev/tty
	printf 'cron:      %s\n' "$cron" >/dev/tty
	printf 'workspace: %s\n' "$workspace" >/dev/tty
	printf 'agent:     %s\n' "$agent" >/dev/tty
	printf 'model:     %s\n' "$model" >/dev/tty
	printf 'auto_close: %s\n' "$auto_close" >/dev/tty
	printf 'command:   %s\n' "$command" >/dev/tty
	printf 'directory: %s\n' "$directory" >/dev/tty
	if [ -n "$wiz_repofile" ]; then
		printf 'file:      %s\n' "$wiz_repofile" >/dev/tty
	else
		printf 'file:      %s\n' "$ACTIONS_DIR/$name.toml" >/dev/tty
	fi
	printf 'enabled:   true (starts live)\n---\n' >/dev/tty
	if ! wizard_confirm "Save"; then
		printf 'Discarded.\n' >/dev/tty
		return 0
	fi
	tmp="$(mktemp "${TMPDIR:-/tmp}/automation-new.XXXXXX")"
	trap 'rm -f "$tmp"' RETURN
	A_name="$name"
	A_description="$description"
	A_cron="$cron"
	A_workspace="$workspace"
	A_agent="$agent"
	A_model="$model"
	A_auto_close="$auto_close"
	A_command="$command"
	A_directory="$directory"
	A_enabled="true"
	if [ -n "$wiz_repofile" ]; then
		append_block "$tmp" || return 1
		A_error=""
		parse_entry "$tmp" 1
		if [ -n "$A_error" ]; then
			printf 'Internal validation failed: %s\n' "$A_error" >/dev/tty
			return 1
		fi
		if [ ! -f "$wiz_repofile" ]; then
			{
				printf '# herdr-automations for %s\n' "$wiz_root"
				printf '#\n# One [[automation]] block per automation. The daemon\n'
				printf '# re-reads this file every tick, so edits apply within\n'
				printf '# a minute with no restart.\n'
			} >"$wiz_repofile"
			wiz_fresh=true
		else
			wiz_fresh=false
		fi
		register_repo "$wiz_root"
		if [ "$wiz_fresh" = true ]; then
			mig="$(migrate_globals "$wiz_repofile")"
			printf 'Global dir: %s.\n' "$mig" >/dev/tty
		fi
		cat "$tmp" >>"$wiz_repofile"
		rm -f "$tmp"
		trap - RETURN
		log_msg "$name	new	manual	ok	created via wizard (enabled) in $wiz_root"
		printf 'Wrote %s (live).\n' "$wiz_repofile" >/dev/tty
	else
		write_flat "$tmp" || return 1
		A_error=""
		parse_entry "$tmp" 0
		if [ -n "$A_error" ]; then
			printf 'Internal validation failed: %s\n' "$A_error" >/dev/tty
			return 1
		fi
		mv "$tmp" "$ACTIONS_DIR/$name.toml"
		trap - RETURN
		log_msg "$name	new	manual	ok	created via wizard (enabled)"
		printf 'Wrote %s (live).\n' "$ACTIONS_DIR/$name.toml" >/dev/tty
	fi
}

cmd_enable_disable() {
	# $1=true|false $2=name: flip enabled inside the entry's own block.
	local want="$1" name="$2" entry file rest block label tmp
	entry="$(find_entry "$name")" || return 1
	file="${entry%%$'\t'*}"
	rest="${entry#*$'\t'}"
	block="${rest%%$'\t'*}"
	label="${rest#*$'\t'}"
	tmp="$(mktemp "${TMPDIR:-/tmp}/automation-edit.XXXXXX")"
	set_entry_key "$file" "$block" enabled "$want" >"$tmp" && mv "$tmp" "$file"
	parse_entry "$file" "$block" || true
	printf '%s: enabled = %s (%s)\n' "${A_name:-$name}" "$want" "$label"
}

cmd_open() {
	# $1=name: focus the workspace of its last run (jump back into the agent).
	local name="$1" entry file rest block ws_id
	entry="$(find_entry "$name")" || return 1
	file="${entry%%$'\t'*}"
	rest="${entry#*$'\t'}"
	block="${rest%%$'\t'*}"
	parse_entry "$file" "$block"
	if [ -n "$A_error" ]; then
		printf '%s\n' "$A_error" >&2
		return 1
	fi
	ws_id="$(last_workspace "$A_name" 2>/dev/null || true)"
	if [ -z "$ws_id" ]; then
		ws_id="$(resolve_workspace_id "$A_workspace")"
	fi
	if [ -z "$ws_id" ]; then
		printf '%s has no workspace yet (never fired?)\n' "$A_name" >&2
		return 1
	fi
	"$HERDR" workspace focus "$ws_id"
}

cmd_history() {
	# [$1=name] [$2=limit]: newest-first run records from the log
	# (current plus rotated), all runs or one automation's.
	local name="${1:-}" limit="${2:-20}" log
	case "$limit" in
	'' | *[!0-9]*) limit=20 ;;
	esac
	printf '%-24s %-20s %-8s %-7s %s\n' "WHEN" "NAME" "TRIGGER" "STATUS" "DETAIL"
	{
		for log in "$LOG_FILE" "$LOG_FILE.1"; do
			[ -f "$log" ] || continue
			cat "$log"
		done
	} | awk -F'\t' -v name="$name" -v limit="$limit" '
		$3 == "run" && (name == "" || $2 == name) { lines[n++] = $0 }
		END { start = (n > limit ? n - limit : 0); for (i = n - 1; i >= start; i--) print lines[i] }' |
		awk -F'\t' '{ printf "%-24s %-20s %-8s %-7s %s\n", $1, $2, $4, $5, $6 }'
}

# --- main --------------------------------------------------------------------------
main() {
	resolve_paths
	command -v jq >/dev/null 2>&1 || {
		printf 'herdr-automations: need jq on PATH\n' >&2
		exit 1
	}
	show_details() {
		# Uses A_* globals plus A_FILE/A_BLOCK/A_LABEL. Prints the detail table
		# and recent history for one automation.
		local next status sub log
		next="$(next_run_for "$A_cron")"
		status="$(last_info "$A_name")"
		if lock_held "$(run_lock "$A_name")"; then
			status="$status (running)"
		fi
		sub="$A_workspace / $A_agent"
		if [ -n "$A_model" ]; then
			sub="$sub ($A_model)"
		fi
		printf '\n=== %s ===\n' "$A_name" >/dev/tty
		if [ -n "$A_description" ]; then
			printf '%s\n' "$A_description" >/dev/tty
		fi
		printf 'Source:    %s\n' "$A_LABEL" >/dev/tty
		printf 'File:      %s (entry %s)\n' "$A_FILE" "$A_BLOCK" >/dev/tty
		printf 'Schedule:  %s (next: %s)\n' "$A_cron" "$next" >/dev/tty
		printf 'Runs in:   %s\n' "$sub" >/dev/tty
		printf 'Enabled:   %s\n' "$A_enabled" >/dev/tty
		printf 'Last run:  %s\n' "$status" >/dev/tty
		printf '%s\n' '--- recent history ---' >/dev/tty
		{
			for log in "$LOG_FILE" "$LOG_FILE.1"; do
				[ -f "$log" ] || continue
				cat "$log"
			done
		} 2>/dev/null | awk -F'\t' -v name="$A_name" '$2 == name' |
			tail -n 5 | awk -F'\t' '{ printf "%s  %-8s  %-10s  %s\n", $1, $4, $5, $6 }' >/dev/tty
	}

	# --- live board ---------------------------------------------------------------
	# htop-style interactive table of all automations: vim navigation, live
	# refresh, and run/enable/open actions. Rendered with raw ANSI escapes
	# (no tput dependency); --once prints one static frame for pipes/tests.
	B_N=0
	B_SEL=0
	B_NEXT_MIN=""
	B_SIG=""
	BOARD_MSG=""
	B_FILE=()
	B_BLOCK=()
	B_NAME=()
	B_SCHED=()
	B_EN=()
	B_STATE=()
	B_LAST=()
	B_NEXT=()
	B_REPO=()
	B_OK=()

	board_entry_last() {
		# $1=name -> sets BL_STATUS / BL_WHEN from the last-run record.
		local info stamp
		info="$(last_info "$1")"
		if [ "$info" = "never" ]; then
			BL_STATUS="—"
			BL_WHEN="—"
			return
		fi
		stamp="${info%% *}"
		BL_STATUS="${info##* }"
		BL_WHEN="${stamp:4:2}-${stamp:6:2} ${stamp:8:2}:${stamp:10:2}"
	}

	board_old_next() {
		# $1=name: reprint the cached next-run from the previous snapshot.
		local i
		i=0
		while [ "$i" -lt "$O_N" ]; do
			if [ "${O_NAME[i]}" = "$1" ]; then
				printf '%s' "${O_NEXT[i]}"
				return 0
			fi
			i=$((i + 1))
		done
		return 1
	}

	board_snapshot() {
		# $1=recompute-next(true/false): rebuild the row arrays.
		local file block label ename i name sig
		O_N=$B_N
		O_NAME=()
		O_NEXT=()
		i=0
		while [ "$i" -lt "$B_N" ]; do
			O_NAME[i]="${B_NAME[i]}"
			O_NEXT[i]="${B_NEXT[i]}"
			i=$((i + 1))
		done
		B_N=0
		B_FILE=()
		B_BLOCK=()
		B_NAME=()
		B_SCHED=()
		B_EN=()
		B_STATE=()
		B_LAST=()
		B_NEXT=()
		B_REPO=()
		B_OK=()
		while IFS=$'\t' read -r file block label ename; do
			[ -n "$file" ] || continue
			case "$ename" in
			ERR:* | DUP:*)
				name="${ename#DUP:}"
				name="${name#ERR:}"
				[ -n "$name" ] || name="$(entry_tag "$file" "$block" "$label")"
				i=$B_N
				B_FILE[i]="$file"
				B_BLOCK[i]="$block"
				B_NAME[i]="$name"
				B_SCHED[i]="error"
				B_EN[i]="err"
				B_STATE[i]="error"
				B_LAST[i]="—"
				B_NEXT[i]="—"
				B_REPO[i]="$(repo_short "$label")"
				B_OK[i]="false"
				B_N=$((i + 1))
				continue
				;;
			esac
			parse_entry "$file" "$block"
			if [ -n "$A_error" ]; then
				i=$B_N
				B_FILE[i]="$file"
				B_BLOCK[i]="$block"
				B_NAME[i]="$(entry_tag "$file" "$block" "$label")"
				B_SCHED[i]="error"
				B_EN[i]="err"
				B_STATE[i]="error"
				B_LAST[i]="—"
				B_NEXT[i]="—"
				B_REPO[i]="$(repo_short "$label")"
				B_OK[i]="false"
				B_N=$((i + 1))
				continue
			fi
			i=$B_N
			B_FILE[i]="$file"
			B_BLOCK[i]="$block"
			B_NAME[i]="$A_name"
			B_SCHED[i]="$A_cron"
			if [ "$A_enabled" = "true" ]; then B_EN[i]="on"; else B_EN[i]="off"; fi
			board_entry_last "$A_name"
			B_LAST[i]="$BL_WHEN"
			if lock_held "$(run_lock "$A_name")"; then
				B_STATE[i]="running"
			elif [ "$BL_STATUS" = "—" ]; then
				B_STATE[i]="—"
			else
				B_STATE[i]="$BL_STATUS"
			fi
			if [ "$1" = true ]; then
				B_NEXT[i]="$(next_run_for "$A_cron")"
			else
				B_NEXT[i]="$(board_old_next "$A_name" || true)"
				[ -n "${B_NEXT[i]}" ] || B_NEXT[i]="$(next_run_for "$A_cron")"
			fi
			B_REPO[i]="$(repo_short "$label")"
			B_OK[i]="true"
			B_N=$((i + 1))
		done < <(list_entries)
	}

	board_refresh() {
		# Rebuild rows; recompute next-runs only when the minute rolled over or
		# the entry set changed (statuses are cheap, cron scans are not).
		local cur_min sig sel_name i
		cur_min="$(date +%Y%m%d%H%M)"
		sig="$(list_entries | cut -f4 | tr '\n' '|')"
		sel_name=""
		if [ "$B_N" -gt 0 ] && [ "$B_SEL" -lt "$B_N" ]; then
			sel_name="${B_NAME[B_SEL]}"
		fi
		if [ "$cur_min" != "$B_NEXT_MIN" ] || [ "$sig" != "$B_SIG" ]; then
			board_snapshot true
		else
			board_snapshot false
		fi
		B_NEXT_MIN="$cur_min"
		B_SIG="$sig"
		B_SEL=0
		if [ -n "$sel_name" ]; then
			i=0
			while [ "$i" -lt "$B_N" ]; do
				if [ "${B_NAME[i]}" = "$sel_name" ]; then
					B_SEL=$i
					break
				fi
				i=$((i + 1))
			done
		fi
		if [ "$B_SEL" -ge "$B_N" ]; then
			B_SEL=$((B_N - 1))
		fi
		if [ "$B_SEL" -lt 0 ]; then B_SEL=0; fi
	}

	board_row() {
		# $1=index -> sets ROW_TEXT (plain columns, no escapes).
		local i="$1"
		ROW_TEXT="$(printf '%-8.8s %-20.20s %-14.14s %-3s %-9.9s %-12.12s %-12.12s %s' \
			"${B_STATE[i]}" "${B_NAME[i]}" "${B_SCHED[i]}" "${B_EN[i]}" \
			"${B_LAST[i]}" "${B_NEXT[i]}" "${B_REPO[i]}" "")"
		ROW_TEXT="${ROW_TEXT% }"
	}

	board_header() {
		printf '%-8s %-20s %-14s %-3s %-9s %-12s %-12s %s\n' \
			"STATE" "NAME" "SCHEDULE" "EN" "LAST" "NEXT" "REPO" ""
	}

	board_render() {
		# Full redraw with selection highlight, windowed to terminal height.
		local rows off height i end line daemon
		printf '\033[2J\033[H'
		if daemon_alive; then daemon="daemon: on"; else daemon="daemon: OFF"; fi
		printf '\033[1mherdr-automations board — %d automation(s) — %s — %s\033[0m\n' \
			"$B_N" "$daemon" "$(date '+%H:%M:%S')"
		board_header
		rows="$(stty size </dev/tty 2>/dev/null || printf '24 80')"
		height=$((${rows%% *} - 6))
		[ "$height" -lt 3 ] && height=3
		off=$((B_SEL - height / 2))
		[ "$off" -lt 0 ] && off=0
		while [ "$((off + height))" -gt "$B_N" ] && [ "$off" -gt 0 ]; do off=$((off - 1)); done
		if [ "$B_N" -eq 0 ]; then
			printf '(no automations — create one from the picker + new row)\n'
		else
			i=$off
			end=$((off + height))
			while [ "$i" -lt "$end" ] && [ "$i" -lt "$B_N" ]; do
				board_row "$i"
				line="$ROW_TEXT"
				if [ "$i" -eq "$B_SEL" ]; then
					printf '\033[7m%s\033[0m\n' "$line"
				else
					case "${B_STATE[i]}" in
					running) printf '\033[32m%s\033[0m\n' "$line" ;;
					error) printf '\033[31m%s\033[0m\n' "$line" ;;
					*) printf '%s\n' "$line" ;;
					esac
				fi
				i=$((i + 1))
			done
		fi
		printf '\n[j/k/↑/↓] move  [g/G] top/bottom  [r]un  [e]nable/disable  [o]pen  [R]efresh  [q]uit\n'
		if [ -n "$BOARD_MSG" ]; then
			printf '%s\n' "$BOARD_MSG"
		else
			printf '\n'
		fi
	}

	board_print_once() {
		# Static frame for pipes and tests (no escapes, no interaction).
		local daemon i
		if daemon_alive; then daemon="daemon: on"; else daemon="daemon: OFF"; fi
		printf 'herdr-automations board — %d automation(s) — %s\n' "$B_N" "$daemon"
		board_header
		i=0
		while [ "$i" -lt "$B_N" ]; do
			board_row "$i"
			printf '%s\n' "$ROW_TEXT"
			i=$((i + 1))
		done
	}

	board_cleanup() {
		printf '\033[?25h\033[0m\n'
	}

	board_act() {
		# Run one board action on the selected row; result goes to BOARD_MSG.
		local i="$B_SEL" out
		if [ "$B_N" -eq 0 ]; then
			BOARD_MSG="(no automations)"
			return 0
		fi
		if [ "${B_OK[i]}" != "true" ]; then
			BOARD_MSG="entry has errors — fix the file first"
			return 0
		fi
		case "$1" in
		run)
			if out="$(fire_automation "${B_FILE[i]}" "${B_BLOCK[i]}" manual 2>&1)"; then
				BOARD_MSG="fired ${B_NAME[i]}"
			else
				BOARD_MSG="${out:-failed to fire ${B_NAME[i]}}"
			fi
			;;
		toggle)
			parse_entry "${B_FILE[i]}" "${B_BLOCK[i]}"
			if [ "$A_enabled" = "true" ]; then
				out="$(cmd_enable_disable false "${B_NAME[i]}" 2>&1)"
			else
				out="$(cmd_enable_disable true "${B_NAME[i]}" 2>&1)"
			fi
			BOARD_MSG="$out"
			;;
		open)
			if out="$(cmd_open "${B_NAME[i]}" 2>&1)"; then
				BOARD_MSG="focused ${B_NAME[i]}"
			else
				BOARD_MSG="$out"
			fi
			;;
		esac
	}

	cmd_board() {
		# Live htop-style board, or one static frame with --once.
		local key rest
		board_refresh
		if [ "${1:-}" = "--once" ]; then
			board_print_once
			return 0
		fi
		if ! exec 3</dev/tty 2>/dev/null; then
			printf 'automations.sh board needs an interactive terminal (try board --once)\n' >&2
			return 1
		fi
		exec 3<&-
		if [ ! -t 1 ]; then
			board_print_once
			return 0
		fi
		trap 'board_cleanup' EXIT INT TERM
		printf '\033[?25l'
		while :; do
			board_refresh
			board_render
			BOARD_MSG=""
			key=""
			IFS= read -rsn1 -t 2 key </dev/tty || true
			case "$key" in
			"") ;;
			$'\x1b')
				rest=""
				IFS= read -rsn2 -t 1 rest </dev/tty || true
				case "$rest" in
				'[A' | '[H') B_SEL=$((B_SEL - 1)) ;;
				'[B' | '[F') B_SEL=$((B_SEL + 1)) ;;
				esac
				;;
			j) B_SEL=$((B_SEL + 1)) ;;
			k) B_SEL=$((B_SEL - 1)) ;;
			g) B_SEL=0 ;;
			G) B_SEL=$((B_N - 1)) ;;
			r) board_act run ;;
			e) board_act toggle ;;
			o) board_act open ;;
			R) B_NEXT_MIN="" ;;
			q | Q) return 0 ;;
			esac
			if [ "$B_SEL" -lt 0 ]; then B_SEL=0; fi
			if [ "$B_N" -gt 0 ] && [ "$B_SEL" -ge "$B_N" ]; then B_SEL=$((B_N - 1)); fi
		done
	}

	cmd_show() {
		# $1=name: details view with actions, for the picker (Enter) and the CLI.
		# Needs a tty: picker rows carry close_on_exit=false so the popup survives.
		local name="$1" entry file rest block label act
		entry="$(find_entry "$name")" || return 1
		file="${entry%%$'\t'*}"
		rest="${entry#*$'\t'}"
		block="${rest%%$'\t'*}"
		label="${rest#*$'\t'}"
		if ! exec 3</dev/tty 2>/dev/null; then
			printf 'automations.sh show needs an interactive terminal\n' >&2
			return 1
		fi
		exec 3<&-
		while :; do
			parse_entry "$file" "$block"
			if [ -n "$A_error" ]; then
				printf 'Automation %s is broken: %s\n%s\n' "$name" "$A_error" "$file" >/dev/tty
				return 1
			fi
			A_FILE="$file"
			A_BLOCK="$block"
			A_LABEL="$label"
			show_details
			if [ "$A_enabled" = "true" ]; then
				act="[r]un  [d]isable  [o]pen  [b]ack"
			else
				act="[r]un  [e]nable  [o]pen  [b]ack"
			fi
			wizard_read "Action ($act)" "b" || return 0
			case "$WIZ_VAL" in
			[rR]*) fire_automation "$file" "$block" manual ;;
			[dD]*)
				if [ "$A_enabled" = "true" ]; then
					cmd_enable_disable false "$name"
				fi
				;;
			[eE]*)
				if [ "$A_enabled" != "true" ]; then
					cmd_enable_disable true "$name"
				fi
				;;
			[oO]*) cmd_open "$name" || true ;;
			*) return 0 ;;
			esac
			printf '\n' >/dev/tty
		done
	}

	cmd_repos() {
		# [add <path>|remove <path>]: manage the repo registry (default: list).
		local reg repo tmp
		reg="$(registry_file)"
		case "${1:-}" in
		"")
			if [ ! -f "$reg" ]; then
				printf 'no repos registered\n'
				return 0
			fi
			while IFS= read -r repo; do
				[ -n "$repo" ] || continue
				if [ -f "$repo/$REPO_FILENAME" ]; then
					printf '%s (has automations file)\n' "$repo"
				else
					printf '%s (no automations file yet)\n' "$repo"
				fi
			done <"$reg"
			;;
		add)
			[ -n "${2:-}" ] || {
				printf 'usage: automations.sh repos add <path>\n' >&2
				return 2
			}
			repo="$(cd "${2}" 2>/dev/null && pwd)" || {
				printf 'not a directory: %s\n' "$2" >&2
				return 1
			}
			register_repo "$repo"
			printf 'registered %s\n' "$repo"
			;;
		remove)
			[ -n "${2:-}" ] || {
				printf 'usage: automations.sh repos remove <path>\n' >&2
				return 2
			}
			[ -f "$reg" ] || return 0
			tmp="$(mktemp "${TMPDIR:-/tmp}/automation-repos.XXXXXX")"
			grep -vxF "${2}" "$reg" >"$tmp" || true
			mv "$tmp" "$reg"
			printf 'removed %s\n' "$2"
			;;
		*)
			printf 'usage: automations.sh repos [add <path>|remove <path>]\n' >&2
			return 2
			;;
		esac
	}

	case "${1:-}" in
	daemon)
		shift
		cmd_daemon "$@"
		;;
	tick) tick_once ;;
	list) cmd_list ;;
	status) cmd_status ;;
	rows) cmd_rows ;;
	new) cmd_new ;;
	board) cmd_board "${2:-}" ;;
	show)
		[ -n "${2:-}" ] || {
			printf 'usage: automations.sh show <name>\n' >&2
			exit 2
		}
		cmd_show "$2"
		;;
	repos)
		shift
		cmd_repos "$@"
		;;
	history) cmd_history "${2:-}" "${3:-}" ;;
	open)
		[ -n "${2:-}" ] || {
			printf 'usage: automations.sh open <name>\n' >&2
			exit 2
		}
		cmd_open "$2"
		;;
	run)
		[ -n "${2:-}" ] || {
			printf 'usage: automations.sh run <name>\n' >&2
			exit 2
		}
		entry="$(find_entry "$2")" || exit 1
		file="${entry%%$'\t'*}"
		rest="${entry#*$'\t'}"
		block="${rest%%$'\t'*}"
		fire_automation "$file" "$block" manual
		;;
	enable | disable)
		[ -n "${2:-}" ] || {
			printf 'usage: automations.sh %s <name>\n' "$1" >&2
			exit 2
		}
		if [ "$1" = "enable" ]; then
			cmd_enable_disable true "$2"
		else
			cmd_enable_disable false "$2"
		fi
		;;
	*)
		printf 'usage: automations.sh [daemon [--detach]|tick|list|status|rows|new|show <name>|board [--once]|repos [add|remove <path>]|history [name]|open <name>|run <name>|enable <name>|disable <name>]\n' >&2
		exit 2
		;;
	esac
}

main "$@"
