# justfile - Command runner for nixos-config-v2

# Default recipe to display help information
default:
    @just --list

# Default Darwin configuration hostname (override with: just <recipe> HOST=<name>)
HOST := "endor"

# Default NixOS configuration hostname (override with: just <recipe> NHOST=<name>)
NHOST := "coruscant"

# Default first-install NixOS configuration (must include Disko)
NINSTALL := "coruscant"

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
    nix run nixpkgs#nixfmt -- **/*.nix

# Find dead/unused code in Nix files
deadnix:
    deadnix .

# Run pre-commit and validate configuration (deep evaluation, catches type errors in home-manager)
check:
    #!/usr/bin/env bash
    set -euo pipefail
    nix flake check --all-systems
    if command -v nh &> /dev/null; then
        nh darwin build --dry .#darwinConfigurations.{{ HOST }}
    else
        darwin-rebuild build --flake .#darwinConfigurations.{{ HOST }}
    fi

# Deep validation helper (alias for check)
validate: check

# Build the Darwin configuration without activating
build:
    #!/usr/bin/env bash
    set -euo pipefail
    if command -v nh &> /dev/null; then
        nh darwin build .#darwinConfigurations.{{ HOST }}
    else
        darwin-rebuild build --flake .#darwinConfigurations.{{ HOST }}
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
        nh darwin switch .#darwinConfigurations.{{ HOST }}
    else
        sudo darwin-rebuild switch --flake .#darwinConfigurations.{{ HOST }}
    fi

    # Send system notification on successful completion
    if command -v terminal-notifier &> /dev/null; then
        terminal-notifier -title "✅ Nix-Darwin Switch Complete" -message "System configuration updated successfully!" -timeout 5
    elif command -v osascript &> /dev/null; then
        osascript -e 'display notification "System configuration updated successfully!" with title "✅ Nix-Darwin Switch Complete"'
    fi

# Verify SSD boot layout after nixos-anywhere install
# Returns 0 if valid, 1 if invalid (prints diagnostics)
# TARGET: SSH target (e.g. root@coruscant-installer.local)
# PASSWORD: SSH password (default: installer)
nixos-verify-boot TARGET="" PASSWORD="installer":
    #!/usr/bin/env bash
    set -euo pipefail
    TARGET="{{ TARGET }}"
    if [ -z "$TARGET" ]; then
        TARGET="root@{{ NHOST }}-installer.local"
    fi
    PASSWORD="{{ PASSWORD }}"

    # Build SSH command — try key auth first, fall back to sshpass
    ssh_cmd() {
        if ssh -o StrictHostKeyChecking=no -o BatchMode=yes "$TARGET" "$@" 2>/dev/null; then
            return 0
        elif command -v sshpass &>/dev/null; then
            sshpass -p "$PASSWORD" ssh -o StrictHostKeyChecking=no "$TARGET" "$@"
        else
            echo "ERROR: SSH key auth failed and sshpass not installed"
            echo "Install sshpass: brew install hudochenkov/sshpass/sshpass"
            exit 1
        fi
    }

    echo "Verifying boot layout on $TARGET..."
    FAIL=0

    # Run all checks in a single SSH call to avoid rate limiting
    CHECKS=$(ssh_cmd 'echo "PARTS:"; lsblk -ln -o NAME,SIZE,TYPE /dev/sda 2>/dev/null; echo "FW:"; ls /mnt/boot/firmware/config.txt /mnt/boot/firmware/broadcom/ /mnt/boot/firmware/nixos/default/kernel.img /mnt/boot/firmware/nixos/default/initrd /mnt/boot/firmware/nixos/default/cmdline.txt 2>/dev/null; echo "CONFIG:"; grep -E "^(kernel|os_prefix)=" /mnt/boot/firmware/config.txt 2>/dev/null; echo "STORE:"; test -d /mnt/nix/store && echo "$(ls /mnt/nix/store | wc -l) entries"' || true)
    echo "$CHECKS"

    if ! echo "$CHECKS" | grep -q "part"; then
        echo "FAIL: No partitions found on /dev/sda"
        FAIL=1
    fi
    if ! echo "$CHECKS" | grep -q "config.txt"; then
        echo "FAIL: /mnt/boot/firmware/config.txt not found"
        FAIL=1
    fi
    if ! echo "$CHECKS" | grep -q "kernel=kernel.img"; then
        echo "FAIL: config.txt does not set kernel=kernel.img"
        FAIL=1
    fi
    if ! echo "$CHECKS" | grep -q "os_prefix=nixos/default/"; then
        echo "FAIL: config.txt does not set os_prefix=nixos/default/"
        FAIL=1
    fi
    if ! echo "$CHECKS" | grep -q "kernel.img"; then
        echo "FAIL: kernel.img not found in /mnt/boot/firmware/nixos/default/"
        FAIL=1
    fi
    if ! echo "$CHECKS" | grep -q "initrd"; then
        echo "FAIL: initrd not found in /mnt/boot/firmware/nixos/default/"
        FAIL=1
    fi
    if ! echo "$CHECKS" | grep -qE "[0-9]+ entries"; then
        echo "FAIL: /mnt/nix/store is empty — NixOS not installed"
        FAIL=1
    fi

    if [ "$FAIL" -eq 0 ]; then
        echo "OK: Boot layout verified"
        exit 0
    else
        echo "BOOT LAYOUT VERIFICATION FAILED — not rebooting"
        exit 1
    fi

# One-shot NixOS install on Raspberry Pi from the minimal installer image
# Copies nixos-files/ to target root when that directory exists
# TARGET: optional hostname/IP (default: {{ NHOST }}-installer.local)
# CONFIG: NixOS configuration to install (default: {{ NINSTALL }})
# SKIP_DISK/skip_disk: set to "1" or "true" to skip drive partitioning/formatting (reuse existing layout)
nixos-init TARGET="" CONFIG=NINSTALL:
    #!/usr/bin/env bash
    set -euo pipefail
    EXTRA_FILES_ARGS=()
    if [ -d ./nixos-files ]; then
        EXTRA_FILES_ARGS+=(--extra-files ./nixos-files)
    else
        echo "No ./nixos-files directory found; continuing without extra files."
    fi
    TARGET="{{ TARGET }}"
    if [ -z "$TARGET" ]; then
        TARGET="{{ NHOST }}-installer.local"
    fi
    SKIP_DISK="${SKIP_DISK:-${skip_disk:-0}}"
    if [ "$SKIP_DISK" = "1" ] || [ "$SKIP_DISK" = "true" ]; then
        PHASES="install"
        echo "Skipping disk partitioning (SKIP_DISK=$SKIP_DISK)..."
    else
        PHASES="disko,install"
    fi
    echo "Installing NixOS on $TARGET via nixos-anywhere..."
    echo "(kexec unsupported on Raspberry Pi — skipping)"
    SSHPASS="installer" nix run github:nix-community/nixos-anywhere -- \
      "${EXTRA_FILES_ARGS[@]}" \
      --flake .#{{ CONFIG }} \
      --env-password \
      --phases "$PHASES" \
      --build-on remote \
      root@$TARGET

    echo ""
    echo "Install complete. Verifying boot layout..."
    echo ""
    just nixos-verify-boot "root@$TARGET" || {
      echo ""
      echo "Aborting — fix the issue and re-run: just nixos-init"
      exit 1
    }

    echo ""
    echo "Shutting down $TARGET..."
    sshpass -p installer ssh -o StrictHostKeyChecking=no "root@$TARGET" "shutdown now" || true
    echo "Done. Remove the SD card, then power on the Pi to boot from SSD."

# Build the NixOS configuration for Raspberry Pi
nixos-build:
    #!/usr/bin/env bash
    set -euo pipefail
    nix build .#nixosConfigurations.{{ NHOST }}.config.system.build.toplevel --out-link result-nixos

# Build and flash an SD card image for the Pi (device e.g. /dev/sda)
# If result-sd-ci/ has a pre-built image, prompts whether to use it
nixos-flash DEVICE:
    #!/usr/bin/env bash
    set -euo pipefail
    CI_IMGS=(result-sd-ci/*.img.zst)
    if [ -f "${CI_IMGS[0]}" ]; then
        echo "Found CI-built image: ${CI_IMGS[0]}"
        read -p "Use this image instead of building locally? [Y/n] " -r
        if [[ $REPLY =~ ^[Yy]?$ ]]; then
            IMG="${CI_IMGS[0]}"
        fi
    fi
    if [ -z "${IMG-}" ]; then
        nix build .#nixosConfigurations.{{ NHOST }}-sd-image.config.system.build.sdImage --out-link result-sd
        IMG="result-sd/sd-image/"
    fi
    if [ -d "$IMG" ]; then
        IMG=$(echo "$IMG"/*.img.zst)
    fi
    if [ ! -e "{{ DEVICE }}" ]; then
        echo "ERROR: Device {{ DEVICE }} does not exist."
        exit 1
    fi
    echo "About to overwrite {{ DEVICE }} with $IMG"
    read -p "Type '{{ DEVICE }}' to continue: " -r CONFIRM
    if [ "$CONFIRM" != "{{ DEVICE }}" ]; then
        echo "Aborted."
        exit 1
    fi
    unzstd -d -f "$IMG" -o /tmp/nixos-sd-image-{{ NHOST }}.img
    sudo dd if=/tmp/nixos-sd-image-{{ NHOST }}.img of={{ DEVICE }} bs=1M status=progress conv=fsync

    echo ""
    echo "Verifying flash (spot check first 10MB)..."
    sync
    RDEVICE=$(echo "{{ DEVICE }}" | sed 's|/dev/disk|/dev/rdisk|')
    IMG_SPOT=$(dd if=/tmp/nixos-sd-image-{{ NHOST }}.img bs=1M count=10 2>/dev/null | shasum -a 256 | cut -d' ' -f1)
    echo "Image (first 10MB): $IMG_SPOT"
    DEV_SPOT=$(sudo dd if="$RDEVICE" bs=1M count=10 2>/dev/null | shasum -a 256 | cut -d' ' -f1) || true
    echo "Device (first 10MB): $DEV_SPOT"
    if [ "$IMG_SPOT" = "$DEV_SPOT" ]; then
        echo "✅ Flash verified successfully!"
    else
        echo "❌ Verification FAILED — checksum mismatch!"
        exit 1
    fi

# Build SD image via GitHub Actions and download it
nixos-build-ci:
    #!/usr/bin/env bash
    set -euo pipefail
    if ! command -v gh &> /dev/null; then
        echo "gh (GitHub CLI) is required. Install it with: brew install gh"
        exit 1
    fi
    PREVIOUS_RUN_ID=$(gh run list \
      --workflow build-sd-image.yml \
      --branch main \
      --event workflow_dispatch \
      --limit 1 \
      --json databaseId \
      --jq '.[0].databaseId // empty')
    echo "Triggering CI build for {{ NHOST }}..."
    gh workflow run build-sd-image.yml --ref main --field host={{ NHOST }}
    echo "Waiting for GitHub to create the workflow run..."
    RUN_ID=""
    for _ in {1..12}; do
        RUN_ID=$(gh run list \
          --workflow build-sd-image.yml \
          --branch main \
          --event workflow_dispatch \
          --limit 1 \
          --json databaseId \
          --jq '.[0].databaseId // empty')
        if [ -n "$RUN_ID" ] && [ "$RUN_ID" != "$PREVIOUS_RUN_ID" ]; then
            break
        fi
        sleep 5
    done
    if [ -z "$RUN_ID" ]; then
        echo "ERROR: No workflow_dispatch run found for build-sd-image.yml on main."
        exit 1
    elif [ "$RUN_ID" = "$PREVIOUS_RUN_ID" ]; then
        echo "ERROR: Timed out waiting for a new build-sd-image.yml run."
        exit 1
    fi
    echo "Run ID: $RUN_ID"
    echo "Waiting for build to complete (this takes ~30-60 min)..."
    gh run watch "$RUN_ID" --exit-status
    echo "Downloading artifact..."
    [ -d result-sd-ci ] && rm -rf result-sd-ci
    gh run download "$RUN_ID" --name "nixos-sd-image-{{ NHOST }}" --dir result-sd-ci
    echo "Image saved to result-sd-ci/"

# Deploy NixOS configuration to Raspberry Pi via SSH
# TARGET: optional hostname/IP (default: {{ NHOST }}.local)
nixos-deploy TARGET="":
    #!/usr/bin/env bash
    set -euo pipefail
    TARGET="{{ TARGET }}"
    if [ -z "$TARGET" ]; then
        TARGET="{{ NHOST }}.local"
    fi
    nixos-rebuild switch --flake .#{{ NHOST }} --target-host root@$TARGET --build-host root@$TARGET --use-remote-sudo

# Deploy NixOS configuration to Raspberry Pi with custom IP
nixos-deploy-ip IP:
    #!/usr/bin/env bash
    set -euo pipefail
    nixos-rebuild switch --flake .#{{ NHOST }} --target-host root@{{ IP }} --build-host root@{{ IP }} --use-remote-sudo

# Show NixOS generations on remote host
nixos-generations:
    #!/usr/bin/env bash
    set -euo pipefail
    nixos-rebuild --list-generations --flake .#{{ NHOST }} --target-host root@{{ NHOST }}.local

# Rollback NixOS on remote host
nixos-rollback:
    #!/usr/bin/env bash
    set -euo pipefail
    nixos-rebuild --rollback --flake .#{{ NHOST }} --target-host root@{{ NHOST }}.local

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

# Backup the sops age key to 1Password as a document
backup-key:
    #!/usr/bin/env bash
    set -euo pipefail
    KEYFILE="$HOME/.config/sops/age/keys.txt"
    if [ ! -f "$KEYFILE" ]; then
        echo "ERROR: Age key not found at $KEYFILE. Run 'just init-sops' first."
        exit 1
    fi
    if ! command -v op &> /dev/null; then
        echo "ERROR: 1Password CLI (op) is required. Install it via: brew install 1password-cli"
        exit 1
    fi
    echo "Storing age key in 1Password..."
    op document create "$KEYFILE" --title "sops-nix age key" --tags "sops-nix,age-key"
    echo "Done. The key can be restored from 1Password if needed."

# Edit sops-encrypted secrets in $EDITOR (default: secrets/default.yaml)
edit-secrets FILE="secrets/default.yaml":
    #!/usr/bin/env bash
    set -euo pipefail
    if [ ! -f "{{ FILE }}" ]; then
        echo "File not found: {{ FILE }}"
        exit 1
    fi
    nix shell nixpkgs#sops nixpkgs#age -c sops "{{ FILE }}"

# Generate an age key for sops-nix (idempotent — skips if key exists)
init-sops:
    #!/usr/bin/env bash
    set -euo pipefail
    KEYFILE=~/.config/sops/age/keys.txt
    mkdir -p "$(dirname "$KEYFILE")"
    if [ -f "$KEYFILE" ]; then
        echo "Age key already exists at $KEYFILE"
        echo "Public key:"
        grep "^# public key:" "$KEYFILE"
    else
        nix shell nixpkgs#age -c age-keygen -o "$KEYFILE"
        echo ""
        echo "Age key created at $KEYFILE"
        echo "Add this public key to .sops.yaml:"
        grep "^# public key:" "$KEYFILE"
    fi

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
        nh darwin switch --dry-run .#darwinConfigurations.{{ HOST }}
    else
        darwin-rebuild build --flake .#darwinConfigurations.{{ HOST }}
        nvd diff /run/current-system ./result
    fi

# Setup work SSH keys and configuration
setup-work-ssh:
    ./scripts/setup-work-ssh.sh

# Check for available updates (pulls if flake.lock changed, notifies via macOS)
check-updates:
    ./scripts/check-for-updates.sh

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

# Trigger flake update via Dependabot
trigger-update-flake-lock:
    @echo "Flake.lock updates are managed automatically by Dependabot."
    @echo "See .github/dependabot.yml - runs weekly on Mondays."
    @echo "To update manually: just update"
