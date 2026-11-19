#!/usr/bin/env bash
# Kiri's engine state and running containers for the OmniShell bar.
#
# Kiri draws its own menu bar item as an NSStatusItem inside its app, and macOS
# gives no way to place that item in another bar, so the widget cannot reuse it.
# These are Kiri's own status endpoints instead: `/kiri/resources` reports
# whether the VM is awake and how big it is, `/containers/json` is the Docker
# API's container list.
#
#   kiri.state       awake | asleep
#   kiri.count       running containers
#   kiri.cpus        the VM's CPUs
#   kiri.memory_mib  the VM's memory ceiling
#   kiri.rows        one "name<TAB>image<TAB>status" line per running container
#
# Two things keep this cheap:
#
# - `X-Kiri-Background: 1` is Kiri's own marker for a request that is not use.
#   Those skip the idle timer (`daemon/api.rs`), so polling every 5 s does not
#   keep the VM up; the 8 GB it holds still goes back to macOS after 60 s idle.
# - Containers are only listed while the VM is awake. `/containers/json` boots
#   it, and waking the VM just to draw an empty list would defeat the sleep.
#
# Values last until OmniWM quits, so an unchanged state is re-pushed every 30
# seconds: a relaunched bar would otherwise draw nothing until Kiri changed. A
# failed push is retried on the next tick.

set -uo pipefail

socket="$HOME/.kiri/run/docker.sock"
tick=5
refresh=30

keys=(kiri.state kiri.count kiri.cpus kiri.memory_mib kiri.rows)
vals=("" "" "" "" "")
last=""
last_push=0

# One `omniwmctl shell set` per value, or an unset for an empty one.
publish() {
	local payload=$1 i rc=0 now=$SECONDS
	if [ "$payload" = "$last" ] && [ $((now - last_push)) -lt $refresh ]; then
		return 0
	fi
	for i in "${!keys[@]}"; do
		if [ -z "${vals[i]}" ]; then
			omniwmctl shell unset "${keys[i]}" >/dev/null 2>&1 || rc=1
		else
			omniwmctl shell set "${keys[i]}" "${vals[i]}" >/dev/null 2>&1 || rc=1
		fi
	done
	if [ $rc -eq 0 ]; then
		last=$payload
		last_push=$now
	fi
}

# GET a daemon path over its unix socket, empty output when the socket is gone.
get() {
	curl -sS --max-time 3 --unix-socket "$socket" -H 'X-Kiri-Background: 1' "http://localhost$1" 2>/dev/null
}

while :; do
	res=$(get /kiri/resources) || res=""
	state=""
	count=""
	cpus=""
	memory=""
	rows=""

	if [ -n "$res" ]; then
		if [ "$(jq -r '.awake' <<<"$res" 2>/dev/null)" = "true" ]; then
			state=awake
			cpus=$(jq -r '.cpus // empty' <<<"$res" 2>/dev/null) || cpus=""
			memory=$(jq -r '.memory_mib // empty' <<<"$res" 2>/dev/null) || memory=""
			list=$(get /containers/json) || list=""
			if [ -n "$list" ]; then
				count=$(jq -r 'length' <<<"$list" 2>/dev/null) || count=""
				rows=$(jq -r '.[] | [((.Names[0] // (.Id[0:12])) | ltrimstr("/")), (.Image // ""), (.Status // "")] | @tsv' <<<"$list" 2>/dev/null) || rows=""
			fi
		else
			state=asleep
		fi
	fi

	# An unreachable daemon leaves `state` empty, which unsets every value and
	# hides the bar item until Kiri is back.
	vals=("$state" "$count" "$cpus" "$memory" "$rows")
	publish "$state|$count|$cpus|$memory|$rows"

	sleep $tick
done
