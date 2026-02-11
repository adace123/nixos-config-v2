#!/usr/bin/env bash

set -e

echo "🚀 Bootstrapping nix-darwin for macOS"
echo ""

# Check if Homebrew is installed
if ! command -v brew &>/dev/null; then
	echo "📦 Homebrew is not installed. Installing Homebrew..."
	/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

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
