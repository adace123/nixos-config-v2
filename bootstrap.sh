#!/usr/bin/env bash

set -e

echo "🚀 Bootstrapping nix-darwin for macOS"
echo ""

# Check if Homebrew is installed
if ! command -v brew &>/dev/null; then
	echo "📦 Homebrew is not installed. Installing Homebrew..."
	# Pinned to a reviewed upstream commit and hash-verified before exec: the
	# installer runs sudo steps, and `HEAD` is whatever upstream serves at fetch
	# time. Bump both values together.
	BREW_INSTALL_REV=7986efac25016e41eed7e471666140c06f9d97cf
	BREW_INSTALL_SHA256=5f333bbe53bc490e51e7ccb1df8779b3dd6ee73a1a7379efda216edb08ccb148
	BREW_TMP="$(mktemp -t brew-install.XXXXXX)"
	trap 'rm -f "$BREW_TMP"' EXIT
	curl -fsSL "https://raw.githubusercontent.com/Homebrew/install/${BREW_INSTALL_REV}/install.sh" -o "$BREW_TMP"
	if [ "$(shasum -a 256 "$BREW_TMP" | awk '{print $1}')" != "$BREW_INSTALL_SHA256" ]; then
		echo "✗ Homebrew installer checksum mismatch — refusing to run it" >&2
		exit 1
	fi
	/bin/bash "$BREW_TMP"

	# Add Homebrew to PATH for Apple Silicon Macs
	if [[ $(uname -m) == "arm64" ]]; then
		echo "✓ Adding Homebrew to PATH for Apple Silicon..."
		eval "$(/opt/homebrew/bin/brew shellenv)"
	fi

	echo "✓ Homebrew installed successfully"
else
	echo "✓ Homebrew is already installed"
fi

echo ""

# Check if Nix is installed
if ! command -v nix &>/dev/null; then
	echo "❌ Nix is not installed. Please install Nix first:"
	echo "   curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install"
	exit 1
fi

echo "✓ Nix is installed"

# Get the current directory
FLAKE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo "✓ Flake directory: $FLAKE_DIR"

# Get the hostname
HOSTNAME=$(scutil --get LocalHostName)
echo "✓ Hostname: $HOSTNAME"

# Check if nix-darwin is already installed
if command -v darwin-rebuild &>/dev/null; then
	echo "✓ nix-darwin is already installed"
	echo ""
	echo "To apply your configuration, run:"
	echo "  darwin-rebuild switch --flake $FLAKE_DIR"
	exit 0
fi

echo ""
echo "📦 Installing nix-darwin..."
echo ""

# Build the nix-darwin system configuration
echo "Building nix-darwin configuration..."
nix build "$FLAKE_DIR#darwinConfigurations.$HOSTNAME.system" --extra-experimental-features "nix-command flakes"

# Run the activation script
echo ""
echo "Activating nix-darwin..."
sudo ./result/sw/bin/darwin-rebuild switch --flake "$FLAKE_DIR"

echo ""
echo "✅ nix-darwin has been installed successfully!"
echo ""
echo "⚠️  You may need to restart your shell for changes to take effect."
echo ""
echo "To rebuild your system in the future, run:"
echo "  sudo darwin-rebuild switch --flake $FLAKE_DIR"
echo ""
echo "Or use the convenience command:"
echo "  just switch"
