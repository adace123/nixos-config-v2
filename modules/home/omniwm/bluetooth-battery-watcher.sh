#!/usr/bin/env bash
# Bluetooth accessory battery for the OmniShell battery widget.
#
# Pushes `bluetooth.batteries`, one "category<TAB>percent<TAB>charging<TAB>name"
# line per connected Bluetooth accessory. The helper reads IOKit's accessory
# power sources — the records behind `pmset -g accps` and Control Center's
# accessory battery — because nothing else in the shell can: widgets cannot
# launch processes, and OmniWM's own `ctx.data.bluetooth` is gated on a Bluetooth
# TCC grant that this machine has not given.
#
# `shell set` values last until OmniWM quits, so an unchanged payload is
# re-pushed every 30 seconds: a relaunched bar would otherwise show nothing
# until a battery changed. A failed push or a failed read leaves the value
# alone and is retried on the next tick.

set -uo pipefail

tick=30
refresh=30

last_payload=""
last_push=0

publish() {
	local rows=$1 rc=0 now=$SECONDS

	if [ "$rows" = "$last_payload" ] && [ $((now - last_push)) -lt $refresh ]; then
		return 0
	fi

	if [ -z "$rows" ]; then
		omniwmctl shell unset bluetooth.batteries >/dev/null 2>&1 || rc=1
	else
		omniwmctl shell set bluetooth.batteries "$rows" >/dev/null 2>&1 || rc=1
	fi

	# A failed push leaves `last_payload` alone, so the next tick retries it.
	if [ $rc -eq 0 ]; then
		last_payload=$rows
		last_push=$now
	fi
}

while :; do
	if rows=$(bluetooth-battery 2>/dev/null); then
		publish "$rows"
	fi
	sleep "$tick"
done
