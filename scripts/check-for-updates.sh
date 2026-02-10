#!/usr/bin/env bash
set -e

# Default values
AUTO_MODE=false
APPLY_UPDATES=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
	case $1 in
	-a | --auto)
		AUTO_MODE=true
		shift
		;;
	--apply)
		APPLY_UPDATES=true
		shift
		;;
	*)
		echo "Unknown option: $1"
		echo "Usage: $0 [-a|--auto] [--apply]"
		echo "  -a, --auto   Run in automatic mode (no user prompts)"
		echo "  --apply      Automatically apply updates after checking (requires --auto)"
		exit 1
		;;
	esac
done

# Validate arguments
if [ "$APPLY_UPDATES" = true ] && [ "$AUTO_MODE" = false ]; then
	echo "Error: --apply can only be used with --auto"
	echo "Usage: $0 --auto --apply"
	exit 1
fi

echo "Checking for updates..."

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Go up one level to get to the project root
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_ROOT" || {
	echo "ERROR: Failed to change to project directory: $PROJECT_ROOT"
	exit 1
}

# Fetch latest from origin
git fetch origin main

LOCAL=$(git rev-parse HEAD)
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
git pull origin main

if [ "$AUTO_MODE" = true ]; then
	if [ "$APPLY_UPDATES" = true ]; then
		# Auto mode with auto apply - apply updates without user interaction
		just switch
	else
		# Auto mode without auto apply - just notify
		echo "Updates pulled. Run 'just switch' to apply."

		# Notify if terminal-notifier available (for automated systems)
		if command -v terminal-notifier >/dev/null 2>&1; then
			terminal-notifier -title "❄️ Nix Update Available" -message "Updates available. Run: just switch" -timeout 0
		fi
	fi
else
	# Interactive mode - ask user if they want to apply updates
	read -p "Do you want to run 'just switch' to apply updates? (y/n) " -n 1 -r
	echo
	if [[ $REPLY =~ ^[Yy]$ ]]; then
		just switch
	else
		echo "Skipping update. Run 'just switch' manually when ready."
	fi
fi
