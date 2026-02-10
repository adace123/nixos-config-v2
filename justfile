# justfile - Command runner for nixos-config-v2

# Default recipe to display help information
default:
    @just --list

install-nix:
    curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install

# Install pre-commit hooks
install-hooks:
    pre-commit install

# Run pre-commit hooks on all files
pre-commit:
    pre-commit run --all-files

# Uninstall pre-commit hooks
uninstall-hooks:
    pre-commit uninstall

# Format all Nix files in the project
fmt:
    nixpkgs-fmt **/*.nix

# Find dead/unused code in Nix files
deadnix:
    deadnix .

# Run all checks (format, lint, deadnix, pre-commit)
check:
    nix flake check --all-systems

# Build the Darwin configuration without activating
build:
    darwin-rebuild build --flake .

install-brew:
    #!/bin/bash
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

    # Add Homebrew to PATH for Apple Silicon Macs
    if [[ $(uname -m) == "arm64" ]]; then
        echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
        eval "$(/opt/homebrew/bin/brew shellenv)"
    else
        # For Intel Macs
        echo 'eval "$(/usr/local/bin/brew shellenv)"' >> ~/.zprofile
        eval "$(/usr/local/bin/brew shellenv)"
    fi

    echo "Homebrew installed successfully!"

# Build and activate the Darwin configuration
switch:
    #!/usr/bin/env bash
    set -euo pipefail
    if ! command -v brew &> /dev/null; then
        echo "Homebrew not installed. Installing it..."
        just install-brew
    fi
    sudo darwin-rebuild switch --flake .

# Show available system generations
generations:
    darwin-rebuild --list-generations

# Rollback to previous generation
rollback:
    darwin-rebuild --rollback

# Update flake inputs
update:
    nix flake update

# Update a specific input (e.g., just update-input nixpkgs)
update-input INPUT:
    nix flake lock --update-input {{ INPUT }}

# Show flake info
info:
    nix flake show

# Show flake metadata
metadata:
    nix flake metadata

# Enter development shell
dev:
    nix develop

# Clean up old generations older than 30 days
clean:
    sudo nix-collect-garbage --delete-older-than 30d

# Clean up and optimize the Nix store
clean-full:
    sudo nix-collect-garbage -d
    nix-store --optimize

# Check flake for errors
check-flake:
    nix flake check

# Diff current and new configuration
diff:
    darwin-rebuild build --flake .
    nvd diff /run/current-system ./result

# Setup work SSH keys and configuration
setup-work-ssh:
    ./scripts/setup-work-ssh.sh

# Check for available updates manually (like the service does)
check-updates:
    #!/bin/bash
    echo "Checking for updates..."
    
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
        echo "  Local:  ''${LOCAL:0:7}"
        echo "  Remote: ''${REMOTE:0:7}"
        exit 0
    fi
    
    echo "❄️ Updates available to flake.lock!"
    echo "  Local:  ''${LOCAL:0:7}"
    echo "  Remote: ''${REMOTE:0:7}"
    echo ""
    echo "Run 'just switch' to apply updates"
    
    # Notify if terminal-notifier available
    if command -v terminal-notifier >/dev/null 2>&1; then
        terminal-notifier -title "❄️ Nix Update Available" -message "Updates available. Run: just switch" -timeout 0
    fi

# Show auto-update service status and trigger manual check
auto-update-status:
    #!/bin/bash
    echo "Nix Config Auto-Update Service"
    echo "=============================="
    echo ""
    echo "This service is managed by nix-darwin."
    echo "It will be automatically installed when you run 'just switch'."
    echo ""
    echo "Configuration:"
    echo "  - Runs daily at 10:00 AM"
    echo "  - Checks for flake.lock changes on origin/main"
    echo "  - Notifies you when updates are available"
    echo "  - You manually run 'just switch' to apply updates"
    echo ""
    echo "Current status:"
    launchctl list | grep nix-config-auto-update || echo "  Service not loaded (run 'just switch' to enable)"
    echo ""
    echo "Logs:"
    echo "  /tmp/nix-darwin-update.log"
    echo ""
    echo "Manual commands:"
    echo "  launchctl start nix-config-auto-update    # Trigger check now"
    echo "  just switch                               # Apply updates"
    echo ""
    read -p "Trigger update check now? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        launchctl start nix-config-auto-update
        echo "Update check triggered. Check notifications and logs."
    fi
