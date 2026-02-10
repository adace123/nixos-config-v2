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

# Function to get password using AppleScript with timeout
get_sudo_password() {
	osascript -e 'display notification "Password required for sudo" with title "Authentication"' \
		-e 'delay 1' \
		-e 'try' \
		-e 'set pwd to text returned of (display dialog "Enter your password to apply NixOS updates:" default answer "" with hidden answer buttons {"Cancel", "OK"} default button "OK" giving up after 300)' \
		-e 'on error number -128' \
		-e 'return "CANCELLED"' \
		-e 'end try' \
		-e 'return pwd'
}

# Function to run command with password
run_with_password() {
	local cmd="$1"
	password=$(get_sudo_password)
	if [ "$password" = "CANCELLED" ]; then
		echo "Password dialog cancelled. Exiting."
		exit 1
	fi

	# Test the password first
	if echo "$password" | sudo -S -v 2>/dev/null; then
		# Password is valid, run the command
		echo "$password" | sudo -S "$cmd"
	else
		echo "Incorrect password entered. Please try again."
		return 1
	fi
}

if [ "$AUTO_MODE" = true ]; then
	if [ "$APPLY_UPDATES" = true ]; then
		# Auto mode with auto apply - apply updates without user interaction
		# Show notification before password dialog
		if command -v terminal-notifier >/dev/null 2>&1; then
			terminal-notifier -title "❄️ NixOS Update" -message "Applying system updates..." -timeout 0
		fi

		# Retry up to 3 times if password is incorrect
		for i in {1..3}; do
			if run_with_password "just switch"; then
				break
			elif [ "$i" -lt 3 ]; then
				echo "Retrying... ($i/3)"
			else
				echo "Failed to authenticate after 3 attempts. Exiting."
				exit 1
			fi
		done
	else
		# Auto mode without auto apply - just notify
		echo "Updates pulled. Run 'just switch' to apply."

		# Notify if terminal-notifier available (for automated systems)
		if command -v terminal-notifier >/dev/null 2>&1; then
			terminal-notifier -title "❄️ NixOS Update Available" -message "System updates are ready to be applied. Run: just switch" -timeout 0
		fi
	fi
else
	# Interactive mode - ask user if they want to apply updates
	read -p "Do you want to run 'just switch' to apply updates? (y/n) " -n 1 -r
	echo
	if [[ $REPLY =~ ^[Yy]$ ]]; then
		# Show notification before password dialog
		if command -v terminal-notifier >/dev/null 2>&1; then
			terminal-notifier -title "❄️ NixOS Update" -message "Preparing to apply system updates..." -timeout 0
		fi

		# Retry up to 3 times if password is incorrect
		for i in {1..3}; do
			if run_with_password "just switch"; then
				break
			elif [ "$i" -lt 3 ]; then
				echo "Retrying... ($i/3)"
			else
				echo "Failed to authenticate after 3 attempts. Exiting."
				exit 1
			fi
		done
	else
		echo "Skipping update. Run 'just switch' manually when ready."
	fi
fi
