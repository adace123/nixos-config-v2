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
    nix flake lock --update-input {{INPUT}}

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

# Run auto-update process manually
auto-update:
    ./scripts/auto-update.sh

# Show auto-update service status
auto-update-status:
    #!/bin/bash
    echo "Nix Config Auto-Update Service"
    echo "=============================="
    echo ""
    echo "This service is managed by nix-darwin."
    echo "It will be automatically installed when you run 'just switch'."
    echo ""
    echo "Configuration:"
    echo "  - Runs weekdays at 9:00 AM Pacific"
    echo "  - Only executes within 9:00-9:15 AM window"
    echo "  - Checks for git changes from origin/main"
    echo "  - Prompts Touch ID for 'just switch' if updates found"
    echo "  - Sends macOS notifications on success/failure"
    echo ""
    echo "Schedule:"
    echo "  - Monday-Friday at 9:00 AM (15-minute execution window)"
    echo "  - Skips execution if outside time window (prevents wake prompts)"
    echo ""
    echo "Current status:"
    launchctl list | grep nix-config-auto-update || echo "  Service not loaded (run 'just switch' to enable)"
    echo ""
    echo "Logs:"
    echo "  ~/.local/share/nix-config-auto-update.log"
    echo "  ~/.local/share/nix-config-auto-update.stdout.log"
    echo "  ~/.local/share/nix-config-auto-update.stderr.log"
    echo ""
    echo "Manual commands:"
    echo "  just auto-update                          # Run update process manually"
    echo "  launchctl start nix-config-auto-update    # Run now (if in time window)"
    echo "  just switch                               # Re-enable via nix"
