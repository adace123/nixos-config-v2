# justfile - Command runner for nixos-config-v2

# Default recipe to display help information
default:
    @just --list

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

# Build and activate the Darwin configuration
switch:
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
