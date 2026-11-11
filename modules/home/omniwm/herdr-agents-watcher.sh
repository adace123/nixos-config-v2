#!/usr/bin/env bash
# Herdr agent attention for the OmniShell bar.
#
# Reads herdr-core's terminal list (`hc ls --json`) and pushes the agents that
# need a person as one widget value, `herdr.rows` — the `herdr-agents` widget
# draws them like Herdr's own sidebar. `hc ls` already carries everything
# needed (the reported status, the agent program and the space/tab label), so
# one cheap call per tick replaces following the event stream, and a missed
# connection can never leave the list stale.
#
# Two values reach the widget:
#
#   herdr.counts  one "state=N" pair per status present (blocked, done, working,
#                 idle, error), for the bar
#   herdr.rows    one "state<TAB>agent<TAB>space / tab" line per agent that is
#                 working, blocked or done, for the list
#
# Raw agent ids go through so the widget can pick the mark. Either value is
# unset when it would be empty.
#
# `shell set` values last until OmniWM quits, so the value is re-pushed every 30
# seconds: a relaunched bar would otherwise list nothing until the next agent
# changed state. A failed push (OmniWM restarting, IPC off) is retried on the
# next tick.

set -uo pipefail

# launchd starts agents with none of the shell's environment. `hc` belongs to
# herdr-core, which the Herdr app installs and updates under ~/.local, so it is
# not in writeShellApplication's runtime inputs.
export PATH="$HOME/.local/bin:/etc/profiles/per-user/${USER:-$(id -un)}/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin${PATH:+:$PATH}"

hc_bin=""
while [ -z "$hc_bin" ]; do
	hc_bin=$(command -v hc 2>/dev/null || true)
	if [ -z "$hc_bin" ]; then
		echo "herdr-agents: no hc on PATH; retrying in 30s" >&2
		sleep 30
	fi
done

# Poll interval, and how often an unchanged list is re-pushed for a bar that
# started after this agent did.
tick=5
refresh=30

last_payload=""
last_push=0

publish() {
	local counts=$1 rows=$2 payload rc=0 now=$SECONDS

	payload="$counts|$rows"
	if [ "$payload" = "$last_payload" ] && [ $((now - last_push)) -lt $refresh ]; then
		return 0
	fi

	if [ -z "$counts" ]; then
		omniwmctl shell unset herdr.counts >/dev/null 2>&1 || rc=1
	else
		omniwmctl shell set herdr.counts "$counts" >/dev/null 2>&1 || rc=1
	fi
	if [ -z "$rows" ]; then
		omniwmctl shell unset herdr.rows >/dev/null 2>&1 || rc=1
	else
		omniwmctl shell set herdr.rows "$rows" >/dev/null 2>&1 || rc=1
	fi

	# A failed push leaves `last_payload` alone, so the next tick retries it.
	if [ $rc -eq 0 ]; then
		last_payload=$payload
		last_push=$now
	fi
}

while :; do
	json=$("$hc_bin" ls --json 2>/dev/null) || {
		sleep 10
		continue
	}

	# One jq pass: only the agents that need a person, one row each. @tsv writes
	# the separator, and every field has a non-empty fallback, so `read` cannot
	# shift columns on an empty value.
	rows=""
	while IFS=$'\t' read -r state agent where; do
		if [ -z "$state" ]; then continue; fi
		if [ ${#rows} -gt 3400 ]; then break; fi
		rows+="${state}"$'\t'"$agent"$'\t'"$where"$'\n'
	done < <(jq -r '
    .terminals[]?
    | select(.status == "blocked" or .status == "done" or .status == "working")
    | [.status, (.agent // "agent"), (.where // .address)] | @tsv
  ' <<<"$json" 2>/dev/null || true)

	counts=$(jq -r '
    [.terminals[]?
     | select(.status == "blocked" or .status == "done" or .status == "working"
              or .status == "idle" or .status == "error")
     | .status]
    | group_by(.) | map("\(.[0])=\(length)") | join(" ")
  ' <<<"$json" 2>/dev/null || true)

	publish "$counts" "$rows"

	sleep $tick
done
