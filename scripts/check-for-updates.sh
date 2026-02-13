#!/usr/bin/env bash
set -e

echo "Checking for updates..."

# Get project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_ROOT"

# Fetch latest from origin
git fetch origin main

LOCAL=$(git rev-parse main)
REMOTE=$(git rev-parse origin/main)

if [ "$LOCAL" = "$REMOTE" ]; then
	echo "✓ Already up to date"
	exit 0
fi

# Check if flake.lock changed
if ! git diff --name-only "$LOCAL" "$REMOTE" | grep -q "flake.lock"; then
	echo "ℹ Changes available but no updates to flake.lock"
	echo "  Local:  ${LOCAL:0:7}"
	echo "  Remote: ${REMOTE:0:7}"
	exit 0
fi

echo "❄️ Updates available to flake.lock!"
echo "  Local:  ${LOCAL:0:7}"
echo "  Remote: ${REMOTE:0:7}"
echo ""

echo "Pulling latest changes..."
git pull origin main --ff-only

# Notify user
if command -v terminal-notifier >/dev/null 2>&1; then
	terminal-notifier -title "❄️ NixOS Update Available" \
		-message "Flake.lock updated. Run 'just switch' to apply." \
		-timeout 0
elif command -v osascript >/dev/null 2>&1; then
	osascript -e 'display notification "Flake.lock updated. Run just switch to apply." with title "❄️ NixOS Update Available"'
fi

echo ""
echo "✓ Updates pulled. Run 'just switch' to apply."
