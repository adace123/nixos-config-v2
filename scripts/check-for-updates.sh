#!/usr/bin/env bash
set -e

# Parse arguments
AUTO_MODE=false
if [[ $1 == "--auto" ]]; then
	AUTO_MODE=true
fi

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

# Fetch latest from origin
git fetch origin main

LOCAL=$(git rev-parse main)
REMOTE=$(git rev-parse origin/main)

# Only check for flake.lock changes, ignore all other changes
if ! git diff --name-only "$LOCAL" "$REMOTE" | grep -q "flake.lock"; then
	echo "✓ Already up to date"
	exit 0
fi

echo "❄️ Updates available to flake.lock!"
echo "  Local:  ${LOCAL:0:7}"
echo "  Remote: ${REMOTE:0:7}"
echo ""

echo "Pulling latest changes..."
if ! git pull --rebase origin main 2>/dev/null; then
	echo "⚠️ Merge conflict - manual intervention needed"
	git rebase --abort 2>/dev/null || true
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
	if command -v terminal-notifier >/dev/null 2>&1; then
		terminal-notifier -title "❄️ NixOS Update Available" \
			-message "Flake.lock updated. Run 'just switch' to apply." \
			-timeout 0
	elif command -v osascript >/dev/null 2>&1; then
		osascript -e 'display notification "Flake.lock updated. Run just switch to apply." with title "❄️ NixOS Update Available"'
	fi
fi

echo ""
echo "✓ Updates pulled. Run 'just switch' to apply."
