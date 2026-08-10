#!/usr/bin/env bash
# Shim installed on PATH as `sudo` by the `just switch` recipe so nh's
# elevation fires a macOS notification at the exact moment authentication
# is required (right before the YubiKey starts blinking), then hands off
# to the real sudo. nh resolves `sudo` via PATH (which::which in
# nh-core), so prepending a directory containing this script intercepts
# every sudo call nh makes.
#
# The YubiKey must be present first: this shim only runs when sudo is
# configured with a U2F factor (u2f_keys exists), so a password-only
# prompt would fail anyway. If the key is missing, show a persistent
# notification and block on a terminal prompt until the user confirms
# they've plugged it in (re-checking via ykman after each Enter). ykman
# is the source of truth (it only lists YubiKeys/security keys), so a
# non-empty `ykman list` means the key is present.
#
# The notification is skipped when sudo's cached timestamp is still valid
# (no prompt will appear). This also dedupes repeated nh elevations:
# after the first successful touch, the timestamp is valid and later
# calls stay silent. `sudo -n` exits before PAM runs, so the probe never
# blocks on the YubiKey itself.
#
# Deliberately no `set -e`: a failing notification must never break sudo.

REAL_SUDO=/usr/bin/sudo

yubikey_present() {
	[ -n "$(ykman list 2>/dev/null)" ]
}

# Require the YubiKey to be present first.
if command -v ykman &>/dev/null; then
	if ! yubikey_present; then
		if [ ! -t 0 ]; then
			echo "Error: no YubiKey detected and stdin is not a terminal (cannot wait for confirmation)." >&2
			exit 1
		fi
		# Persistent notification (no -timeout) until the user plugs in the key.
		if command -v terminal-notifier &>/dev/null; then
			terminal-notifier -title "🔐 YubiKey Required" \
				-message "No YubiKey detected — plug it in, then press Enter here to continue." \
				-sound default
		elif command -v osascript &>/dev/null; then
			osascript -e 'display notification "No YubiKey detected — plug it in, then press Enter to continue." with title "🔐 YubiKey Required" sound name "Ping"'
		fi
		while ! yubikey_present; do
			read -r -p "No YubiKey detected. Plug it in and press Enter (Ctrl-C to abort): " _
		done
	fi
else
	echo "Warning: ykman not found; skipping YubiKey presence check." >&2
fi

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
