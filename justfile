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
    #!/usr/bin/env bash
    if command -v nh &> /dev/null; then
        nh darwin build .#darwinConfigurations.endor
    else
        darwin-rebuild build --flake .#darwinConfigurations.endor
    fi

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
    if command -v nh &> /dev/null; then
        nh darwin switch .#darwinConfigurations.endor
    else
        sudo darwin-rebuild switch --flake .#darwinConfigurations.endor
    fi

    # Send system notification on successful completion
    if command -v terminal-notifier &> /dev/null; then
        terminal-notifier -title "✅ Nix-Darwin Switch Complete" -message "System configuration updated successfully!" -timeout 5
    elif command -v osascript &> /dev/null; then
        osascript -e 'display notification "System configuration updated successfully!" with title "✅ Nix-Darwin Switch Complete"'
    fi

# Show available system generations
generations:
    #!/usr/bin/env bash
    if command -v nh &> /dev/null; then
        nh darwin generations
    else
        darwin-rebuild --list-generations
    fi

# Rollback to previous generation
rollback:
    #!/usr/bin/env bash
    if command -v nh &> /dev/null; then
        nh darwin rollback
    else
        darwin-rebuild --rollback
    fi

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
    #!/usr/bin/env bash
    if command -v nh &> /dev/null; then
        nh clean all --keep-since 30d
    else
        sudo nix-collect-garbage --delete-older-than 30d
    fi

# Clean up and optimize the Nix store
clean-full:
    #!/usr/bin/env bash
    if command -v nh &> /dev/null; then
        nh clean all
    else
        sudo nix-collect-garbage -d
    fi
    nix-store --optimize

# Check flake for errors
check-flake:
    nix flake check

# Diff current and new configuration
diff:
    #!/usr/bin/env bash
    if command -v nh &> /dev/null; then
        nh darwin switch --dry-run .#darwinConfigurations.endor
    else
        darwin-rebuild build --flake .#darwinConfigurations.endor
        nvd diff /run/current-system ./result
    fi

# Setup work SSH keys and configuration
setup-work-ssh:
    ./scripts/setup-work-ssh.sh

# Check for available updates manually (with user interaction)
check-updates:
    #!/bin/bash
    ./scripts/check-for-updates.sh

# Check for updates without user interaction (for automated systems)
check-updates-no-prompt:
    #!/bin/bash
    ./scripts/check-for-updates.sh --auto

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

# Trigger the update-flake-lock workflow via GitHub CLI and follow logs
trigger-update-flake-lock:
    #!/usr/bin/env bash
    if ! command -v gh &> /dev/null; then
        echo "❌ Error: GitHub CLI (gh) is not installed. Please install it first."
        exit 1
    fi
    echo "Triggering update-flake-lock workflow..."
    gh workflow run "Update Flake Lock" --ref main
    echo "✅ update-flake-lock workflow triggered successfully!"
    echo "Waiting for workflow run to start..."
    for i in {1..30}; do
        sleep 3
        echo "Checking for workflow run... ($i/30)"
        RUN_ID=$(gh run list --workflow="Update Flake Lock" --limit=1 --json databaseId --jq '.[0].databaseId')
        if [ -n "$RUN_ID" ]; then
            STATUS=$(gh run view $RUN_ID --json status --jq '.status')
            if [ "$STATUS" != "queued" ] && [ "$STATUS" != "requested" ] && [ "$STATUS" != "waiting" ]; then
                echo "Workflow run $RUN_ID is active with status: $STATUS"
                echo "Following logs for workflow run ID: $RUN_ID"
                gh run watch $RUN_ID
                exit 0
            else
                echo "Workflow run $RUN_ID is still in queue with status: $STATUS"
            fi
        fi
    done
    echo "❌ Could not get the workflow run ID or workflow is still queued after timeout"
