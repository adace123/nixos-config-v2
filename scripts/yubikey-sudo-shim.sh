#!/usr/bin/env bash
# Shim installed on PATH as `sudo` by the `just switch` recipe so nh's
# elevation fires a macOS notification at the exact moment authentication
# is required (right before the YubiKey starts blinking), then hands off
# to the real sudo. nh resolves `sudo` via PATH (which::which in
# nh-core), so prepending a directory containing this script intercepts
# every sudo call nh makes.
#
# The notification is skipped when sudo's cached timestamp is still valid
# (no prompt will appear). This also dedupes repeated nh elevations:
# after the first successful touch, the timestamp is valid and later
# calls stay silent. `sudo -n` exits before PAM runs, so the probe never
# blocks on the YubiKey itself.
#
# Deliberately no `set -e`: a failing notification must never break sudo.

REAL_SUDO=/usr/bin/sudo

# Valid cached credentials → no prompt → no notification.
if "$REAL_SUDO" -n true 2>/dev/null; then
	exec "$REAL_SUDO" "$@"
fi

if command -v terminal-notifier &>/dev/null; then
	terminal-notifier -title "🔐 YubiKey Touch Required" \
		-message "Activation needs sudo — touch your YubiKey (or enter password)." \
		-timeout 8 -sound default
elif command -v osascript &>/dev/null; then
	osascript -e 'display notification "Activation needs sudo — touch your YubiKey (or enter password)." with title "🔐 YubiKey Touch Required" sound name "Ping"'
fi

exec "$REAL_SUDO" "$@"
