#!/usr/bin/env bash
set -euo pipefail

# Manual check: report whether `origin/main` carries a lockfile-only bump, pull
# it, and leave the activation to `just switch`.
#
# A push that touches anything besides `flake.lock` is reported and NOT pulled:
# modules, activation scripts, the justfile and CI all run code, and this script
# is also what a daily agent runs (`--auto`). Only a reviewed `git pull` /
# `just switch` may materialize those. See docs/deployment.md#auto-updates.

# Parse arguments
AUTO_MODE=false
if [[ ${1:-} == "--auto" ]]; then
	AUTO_MODE=true
fi

notify() {
	local title="$1" message="$2"
	if command -v terminal-notifier >/dev/null 2>&1; then
		terminal-notifier -title "$title" -message "$message" -timeout 0
	elif command -v osascript >/dev/null 2>&1; then
		osascript -e "display notification \"$message\" with title \"$title\""
	fi
}

echo "Checking for updates..."

# Get project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_ROOT"

# Rotate log if it exists and is > 1MB
LOG_FILE="/tmp/nix-darwin-update.log"
if [[ -f $LOG_FILE && $(stat -f%z "$LOG_FILE" 2>/dev/null || stat -c%s "$LOG_FILE" 2>/dev/null) -gt 1048576 ]]; then
	mv "$LOG_FILE" "${LOG_FILE}.old"
fi

# Fetch latest from origin. Explicit refspec: `git fetch origin main` updates
# FETCH_HEAD, not necessarily refs/remotes/origin/main.
git fetch --quiet origin '+refs/heads/main:refs/remotes/origin/main'

LOCAL=$(git rev-parse main)
REMOTE=$(git rev-parse refs/remotes/origin/main)

if [[ $LOCAL == "$REMOTE" ]]; then
	echo "✓ Already up to date"
	exit 0
fi

CHANGED=$(git diff --name-only "$LOCAL" "$REMOTE")

# Only a flake.lock bump is routine. Anything else waits for a human.
if ! printf '%s\n' "$CHANGED" | grep -qx 'flake.lock'; then
	echo "✓ No flake.lock changes"
	exit 0
fi

NON_LOCK=$(printf '%s\n' "$CHANGED" | grep -vx 'flake.lock' || true)
if [[ -n $NON_LOCK ]]; then
	COUNT=$(printf '%s\n' "$NON_LOCK" | wc -l | tr -d ' ')
	echo "⚠️ main moved with $COUNT non-lockfile change(s) — not pulling."
	printf '%s\n' "$NON_LOCK" | sed 's/^/    /'
	echo "Review it, then run 'git pull --ff-only' (or 'just switch') yourself."
	if [[ $AUTO_MODE == false ]]; then
		notify "❄️ Nix Config Update Needs Review" "main moved with non-lockfile changes. Review, then run 'just switch'."
	fi
	exit 0
fi

echo "❄️ Updates available to flake.lock!"
echo "  Local:  ${LOCAL:0:7}"
echo "  Remote: ${REMOTE:0:7}"
echo ""

echo "Pulling latest changes..."
if ! git merge --ff-only --quiet "$REMOTE"; then
	echo "⚠️ Merge conflict - manual intervention needed"
	if command -v terminal-notifier >/dev/null 2>&1; then
		terminal-notifier -title "❄️ Nix Config Update Failed" \
			-message "Merge conflict - manual intervention needed" \
			-timeout 0
	elif command -v osascript >/dev/null 2>&1; then
		osascript -e 'display notification "Merge conflict - manual intervention needed" with title "❄️ Nix Config Update Failed"'
	fi
	exit 1
fi

# Notify user (skip in auto mode, e.g., when running from launchd)
if [[ $AUTO_MODE == false ]]; then
	notify "❄️ NixOS Update Available" "Flake.lock updated. Run 'just switch' to apply."
fi

echo ""
echo "✓ Updates pulled. Run 'just switch' to apply."
