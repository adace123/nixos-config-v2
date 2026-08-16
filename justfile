# justfile - Command runner for nixos-config-v2

# Default recipe to display help information
default:
    @just --list

# Default Darwin configuration hostname (override with: just <recipe> HOST=<name>)
# Exported so the DARWIN_* command strings below can use $HOST (just does not
# interpolate {{ }} inside := definitions).
export HOST := "endor"

# Default NixOS configuration hostname (override with: just <recipe> NHOST=<name>)
NHOST := "coruscant"

# Default first-install NixOS configuration (must include Disko)
NINSTALL := "coruscant"

# Flags read as env vars inside nixos-flash; exported so the command-line
# override form also works: just YES=1 VERIFY_ONLY=1 nixos-flash /dev/diskX
# (just rejects overrides for variables that are not declared).
export YES := "0"
export VERIFY_ONLY := "0"

# Each variable self-selects nh vs the darwin-rebuild/nix-collect-garbage fallback at
# runtime, so recipes stay single-line and the fork logic lives in one place.
DARWIN_BUILD := "if command -v nh >/dev/null 2>&1; then nh darwin build .#darwinConfigurations.$HOST; else darwin-rebuild build --flake .#darwinConfigurations.$HOST; fi"
DARWIN_CHECK := "if command -v nh >/dev/null 2>&1; then nh darwin build --dry .#darwinConfigurations.$HOST; else darwin-rebuild build --flake .#darwinConfigurations.$HOST; fi"
DARWIN_SWITCH := "if command -v nh >/dev/null 2>&1; then nh darwin switch .#darwinConfigurations.$HOST; else sudo darwin-rebuild switch --flake .#darwinConfigurations.$HOST; fi"
DARWIN_GENERATIONS := "if command -v nh >/dev/null 2>&1; then nh darwin generations; else darwin-rebuild --list-generations; fi"
DARWIN_ROLLBACK := "if command -v nh >/dev/null 2>&1; then nh darwin rollback; else darwin-rebuild --rollback; fi"
CLEAN_30D := "if command -v nh >/dev/null 2>&1; then nh clean all --keep-since 30d; else sudo nix-collect-garbage --delete-older-than 30d; fi"
CLEAN_ALL := "if command -v nh >/dev/null 2>&1; then nh clean all --optimise; else sudo nix-collect-garbage -d && nix-store --optimize; fi"

# One-time bootstrap (hidden from `just --list`)
[private]
install-nix:
    curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install

# Install pre-commit hooks
[group('workflow')]
[private]
install-hooks:
    pre-commit install

# Uninstall pre-commit hooks
[group('workflow')]
[private]
uninstall-hooks:
    pre-commit uninstall

# Run pre-commit hooks on all files
[group('workflow')]
pre-commit:
    pre-commit run --all-files

# Format all Nix files via the flake formatter (same nixfmt as the pre-commit hook)
[group('workflow')]
fmt:
    nix fmt

# Find dead/unused code in Nix files
[group('workflow')]
deadnix:
    deadnix .

# Run pre-commit, flake check, and validate the Darwin configuration
# (deep evaluation, catches type errors in home-manager)
[group('workflow')]
check:
    #!/usr/bin/env bash
    set -euo pipefail
    pre-commit run --all-files
    nix flake check
    {{ DARWIN_CHECK }}

# Build the Darwin configuration without activating
[group('darwin')]
build:
    {{ DARWIN_BUILD }}

# Install Homebrew (called automatically by `just switch` when brew is missing)
[private]
install-brew:
    #!/bin/bash
    set -euo pipefail
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

    # Add Homebrew to PATH for Apple Silicon Macs (idempotent — don't append twice)
    if [[ $(uname -m) == "arm64" ]]; then
        if ! grep -q "brew shellenv" ~/.zprofile; then
            echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
        fi
        eval "$(/opt/homebrew/bin/brew shellenv)"
    else
        # For Intel Macs
        if ! grep -q "brew shellenv" ~/.zprofile; then
            echo 'eval "$(/usr/local/bin/brew shellenv)"' >> ~/.zprofile
        fi
        eval "$(/usr/local/bin/brew shellenv)"
    fi

    echo "Homebrew installed successfully!"

# Build and activate the Darwin configuration
[group('darwin')]
switch:
    #!/usr/bin/env bash
    set -euo pipefail
    if ! command -v brew &> /dev/null; then
        echo "Homebrew not installed. Installing it..."
        just install-brew
    fi

    # YubiKey touch heads-up at the nh→sudo boundary.
    # nh resolves `sudo` via PATH (which::which in nh-core), so a shim dir
    # prepended here fires a notification at the exact moment nh elevates
    # (right before the key blinks), then execs the real sudo. The terminal
    # password prompt is untouched. See scripts/yubikey-sudo-shim.sh.
    #
    # Only install the shim when the laptop lid is closed (headless / remote
    # via SSH): nobody is at the keyboard, so the shim's YubiKey
    # presence-wait is the only way nh's elevation can succeed. With the lid
    # open the user is at the machine — Touch ID or password auth works, and
    # blocking on the key would just get in the way. AppleClamshellState =
    # Yes means the lid is closed (clamshell mode).
    if [ -f "$HOME/.config/Yubico/u2f_keys" ] &&
        ioreg -r -k AppleClamshellState -d 4 2>/dev/null | grep -q '"AppleClamshellState" = Yes'; then
        SHIM_DIR="$(mktemp -d)"
        trap 'rm -rf "$SHIM_DIR"' EXIT
        cp scripts/yubikey-sudo-shim.sh "$SHIM_DIR/sudo"
        chmod +x "$SHIM_DIR/sudo"
        export PATH="$SHIM_DIR:$PATH"
    fi

    {{ DARWIN_SWITCH }}

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
[group('nixos')]
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
[group('nixos')]
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
[group('nixos')]
nixos-build:
    #!/usr/bin/env bash
    set -euo pipefail
    nix build .#nixosConfigurations.{{ NHOST }}.config.system.build.toplevel --out-link result-nixos

# Flash a NixOS image to a device (SD card, USB stick, …)
# DEVICE: target device, e.g. /dev/disk5 (required)
# IMAGE:  optional path to a pre-built image (.img/.iso/.img.zst/.img.gz/.img.xz);
#         when omitted, uses the <NHOST>-sd-image flake config — a CI-built image
#         from result-sd-ci-<host>/ if available, otherwise built locally.
# NHOST:  host whose '-sd-image' config to build/flash (default: {{ NHOST }})
# YES=1:  skip all interactive prompts (non-interactive use)
# VERIFY_ONLY=1: skip the write and just verify the device against the image
[group('nixos')]
nixos-flash DEVICE IMAGE="":
    #!/usr/bin/env bash
    set -euo pipefail
    HOST="{{ NHOST }}"
    DEV="{{ DEVICE }}"
    IMG=""

    # When YES=1, never block on prompts
    auto() { [ "${YES:-0}" = "1" ]; }

    if [ -n "{{ IMAGE }}" ]; then
        # Explicit image path — no build needed
        IMG="{{ IMAGE }}"
        [ -f "$IMG" ] || { echo "ERROR: image not found: $IMG"; exit 1; }
    fi

    if [ -z "$IMG" ]; then
        # Prefer the newest CI-built image for this host, if one exists
        # (find handles any nesting gh run download may produce)
        CI_IMG=""
        CI_IMG_MTIME=0
        while IFS= read -r f; do
            MT=$(stat -f%m "$f" 2>/dev/null || stat -c%Y "$f")
            if [ "$MT" -gt "$CI_IMG_MTIME" ]; then
                CI_IMG="$f"
                CI_IMG_MTIME="$MT"
            fi
        done < <(find "result-sd-ci-$HOST" -name '*.img.zst' -type f 2>/dev/null)
        if [ -n "$CI_IMG" ]; then
            echo "Found CI-built image: $CI_IMG"
            # Stale check: prefer rebuilding when the image predates the latest commit or flake.lock
            LAST_CHANGE=0
            [ -f flake.lock ] && LAST_CHANGE=$(stat -f%m flake.lock 2>/dev/null || stat -c%Y flake.lock)
            HEAD_TIME=$(git log -1 --format=%ct 2>/dev/null || echo 0)
            [ "$HEAD_TIME" -gt "$LAST_CHANGE" ] && LAST_CHANGE=$HEAD_TIME
            if [ "$CI_IMG_MTIME" -lt "$LAST_CHANGE" ]; then
                echo "⚠️  It is older than the latest commit/flake.lock — config may have changed since it was built."
                if auto; then
                    IMG="$CI_IMG"
                else
                    read -p "Use it anyway? [y/N] " -r
                    [[ $REPLY =~ ^[Yy]$ ]] && IMG="$CI_IMG"
                fi
            else
                if auto; then
                    IMG="$CI_IMG"
                else
                    read -p "Use this image instead of building locally? [Y/n] " -r
                    [[ $REPLY =~ ^[Nn]$ ]] || IMG="$CI_IMG"
                fi
            fi
        fi
    fi

    if [ -z "$IMG" ]; then
        echo "Building SD image for $HOST locally..."
        nix build ".#nixosConfigurations.$HOST-sd-image.config.system.build.sdImage" --out-link "result-sd-$HOST"
        IMG="$(find "result-sd-$HOST" -name '*.img.zst' -type f -print -quit)"
    fi
    if [ -z "$IMG" ] || [ ! -s "$IMG" ]; then
        echo "ERROR: no usable image found ($IMG)"
        exit 1
    fi
    if [ ! -e "$DEV" ]; then
        echo "ERROR: Device $DEV does not exist."
        exit 1
    fi
    echo "About to overwrite $DEV with $IMG ($(du -h "$IMG" | cut -f1))"

    # macOS auto-mounts SD card volumes — unmount them before raw-writing
    if [ "$(uname)" = "Darwin" ] && [[ "$DEV" == /dev/disk* ]]; then
        if ! diskutil unmountDisk "$DEV" 2>/dev/null; then
            sudo diskutil unmountDisk "$DEV" 2>/dev/null \
                || echo "(Note: $DEV was not mounted or is unmountable — continuing)"
        fi
    fi
    if ! auto; then
        read -p "Type '$DEV' to continue: " -r CONFIRM
        if [ "$CONFIRM" != "$DEV" ]; then
            echo "Aborted."
            exit 1
        fi
    fi

    # Decompress when the image is compressed (CI/local builds are .zst; an explicit
    # IMAGE= may be any raw image or a common compression). Only temp copies are removed.
    TEMP_IMG=""
    case "$IMG" in
        *.zst) TEMP_IMG="/tmp/nixos-flash-$HOST-$$.img"; unzstd -d -f "$IMG" -o "$TEMP_IMG" ;;
        *.gz)  TEMP_IMG="/tmp/nixos-flash-$HOST-$$.img"; gzip -d -c "$IMG" > "$TEMP_IMG" ;;
        *.xz)  TEMP_IMG="/tmp/nixos-flash-$HOST-$$.img"; xz -d -c "$IMG" > "$TEMP_IMG" ;;
    esac
    IMG_FILE="${TEMP_IMG:-$IMG}"

    # macOS: write to the raw device (rdisk) — bypasses the buffer cache for much faster dd
    if [ "${VERIFY_ONLY:-0}" = "1" ]; then
        echo "VERIFY_ONLY=1 — skipping write; verifying existing device content against the image..."
    else
        WDEVICE=$(echo "$DEV" | sed 's|/dev/disk|/dev/rdisk|')
        sudo dd if="$IMG_FILE" of="$WDEVICE" bs=1M status=progress conv=fsync
    fi

    echo ""
    echo "Verifying flash (full-image checksum)..."
    sync
    RDEVICE=$(echo "$DEV" | sed 's|/dev/disk|/dev/rdisk|')
    IMG_HASH=$(shasum -a 256 "$IMG_FILE" | awk '{print $1}')
    IMG_SIZE=$(stat -f%z "$IMG_FILE" 2>/dev/null || stat -c%s "$IMG_FILE")
    COUNT=$(( (IMG_SIZE + 1048575) / 1048576 ))
    echo "Hashing first $IMG_SIZE bytes of $RDEVICE (reads the whole image)..."
    # Read to a temp file instead of a pipe: dd's exit status and the actual
    # byte count stay visible, so a flaky reader that errors mid-read can't
    # silently produce a truncated hash (previously hidden by 2>/dev/null with
    # pipefail off — it read ~1.5GB, hashed that, and reported a false mismatch).
    VERIFY_FILE="/tmp/nixos-flash-verify-$$.img"
    if ! sudo dd if="$RDEVICE" bs=1M count="$COUNT" of="$VERIFY_FILE" 2>&1; then
        echo "❌ Read-back failed — the device could not be read (flaky reader or card?)."
        sudo rm -f "$VERIFY_FILE"
        rm -f "$TEMP_IMG"
        exit 1
    fi
    VERIFY_SIZE=$(stat -f%z "$VERIFY_FILE" 2>/dev/null || stat -c%s "$VERIFY_FILE")
    if [ "$VERIFY_SIZE" -lt "$IMG_SIZE" ]; then
        echo "❌ Read-back too short: got $VERIFY_SIZE bytes, expected $IMG_SIZE — device read is unreliable."
        sudo rm -f "$VERIFY_FILE"
        rm -f "$TEMP_IMG"
        exit 1
    fi
    # dd rounds up to 1M blocks; hash only the exact image size (the verify file
    # is root-owned, so no mv/rm without sudo — pipe through head instead)
    DEV_HASH=$(head -c "$IMG_SIZE" "$VERIFY_FILE" | shasum -a 256 | awk '{print $1}')
    sudo rm -f "$VERIFY_FILE"
    echo "Image  (sha256): $IMG_HASH"
    echo "Device (sha256): $DEV_HASH"
    if [ "$IMG_HASH" = "$DEV_HASH" ]; then
        echo "✅ Flash verified successfully!"
        [ -n "$TEMP_IMG" ] && rm -f "$TEMP_IMG"
    else
        echo "❌ Verification FAILED — device content does not match the image!"
        [ -n "$TEMP_IMG" ] && rm -f "$TEMP_IMG"
        exit 1
    fi

# Build SD image via GitHub Actions and download it
# NHOST: host to build (default: {{ NHOST }}; must have a '-sd-image' variant)
[group('nixos')]
nixos-build-ci:
    #!/usr/bin/env bash
    set -euo pipefail
    if ! command -v gh &> /dev/null; then
        echo "gh (GitHub CLI) is required. Install it with: brew install gh"
        exit 1
    fi
    HOST="{{ NHOST }}"
    PREVIOUS_RUN_ID=$(gh run list \
      --workflow build-sd-image.yml \
      --branch main \
      --event workflow_dispatch \
      --limit 1 \
      --json databaseId \
      --jq '.[0].databaseId // empty')
    echo "Triggering CI build for $HOST..."
    gh workflow run build-sd-image.yml --ref main --field host="$HOST"
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
    echo "Waiting for build to complete (native arm64 runner, ~10-30 min)..."
    gh run watch "$RUN_ID" --exit-status
    # Artifact name embeds the commit SHA the image was built from
    SHA=$(gh run view "$RUN_ID" --json headSha --jq '.headSha')
    CI_DIR="result-sd-ci-$HOST"
    echo "Downloading artifact nixos-sd-image-$HOST-$SHA..."
    [ -d "$CI_DIR" ] && rm -rf "$CI_DIR"
    gh run download "$RUN_ID" --name "nixos-sd-image-$HOST-$SHA" --dir "$CI_DIR"
    echo "Image saved to $CI_DIR/"

# Build the NixOS configuration on the remote host (no activation)
# TARGET: hostname or IP (default: {{ NHOST }}.local, e.g. just nixos-remote-build 10.0.0.2)
# Builds on the target itself (--build-host), so run it ahead of a deploy at
# a quiet moment: the heavy compile finishes first, then nixos-deploy only
# needs to activate (store paths already cached).
[group('nixos')]
nixos-remote-build TARGET="":
    #!/usr/bin/env bash
    set -euo pipefail
    TARGET="{{ TARGET }}"
    if [ -z "$TARGET" ]; then
        TARGET="{{ NHOST }}.local"
    fi
    export NIX_SSHOPTS="${NIX_SSHOPTS:+$NIX_SSHOPTS }-4"
    nix run nixpkgs#nixos-rebuild -- build --flake .#{{ NHOST }} --target-host root@$TARGET --build-host root@$TARGET

# Build then activate on a remote NixOS host via SSH
# TARGET: hostname or IP (default: {{ NHOST }}.local, e.g. just nixos-deploy 10.0.0.2)
#
# Build and switch run as separate steps so the host is not restarting all its
# services (HA, zigbee2mqtt, esphome, ...) while still compiling. Activation
# runs detached via systemd-run as root, so an SSH drop (e.g. sshd restarting
# during switch) does not kill it; no --elevate=sudo needed since the SSH
# user is root (the sudo wrapper previously failed with a misleading
# password/exit-4 error and added fragility).
[group('nixos')]
nixos-deploy TARGET="":
    #!/usr/bin/env bash
    set -euo pipefail
    just nixos-remote-build TARGET="{{ TARGET }}"
    TARGET="{{ TARGET }}"
    if [ -z "$TARGET" ]; then
        TARGET="{{ NHOST }}.local"
    fi
    export NIX_SSHOPTS="${NIX_SSHOPTS:+$NIX_SSHOPTS }-4"
    nix run nixpkgs#nixos-rebuild -- switch --flake .#{{ NHOST }} --target-host root@$TARGET --build-host root@$TARGET

# Show NixOS generations on remote host
[group('nixos')]
nixos-generations:
    #!/usr/bin/env bash
    set -euo pipefail
    export NIX_SSHOPTS="${NIX_SSHOPTS:+$NIX_SSHOPTS }-4"
    nix run nixpkgs#nixos-rebuild -- --list-generations --flake .#{{ NHOST }} --target-host root@{{ NHOST }}.local

# Rollback NixOS on remote host
[group('nixos')]
nixos-rollback:
    #!/usr/bin/env bash
    set -euo pipefail
    export NIX_SSHOPTS="${NIX_SSHOPTS:+$NIX_SSHOPTS }-4"
    nix run nixpkgs#nixos-rebuild -- --rollback --flake .#{{ NHOST }} --target-host root@{{ NHOST }}.local

# Tail Home Assistant logs on remote NixOS host via journalctl
# FILTER: optional grep pattern (e.g., "error|recorder|bluetooth")
# LINES: number of lines to show (default: 50)
[group('nixos')]
hass-logs FILTER="" LINES="50":
    #!/usr/bin/env bash
    set -euo pipefail
    CMD="journalctl -flu podman-home-assistant.service -n {{ LINES }} --no-hostname --output cat 2>&1"
    if [ -n "{{ FILTER }}" ]; then
        # Quote the filter so special characters survive the remote shell
        CMD="$CMD | grep -iE $(printf '%q' '{{ FILTER }}')"
    fi
    ssh -4 root@{{ NHOST }}.local "$CMD"

# Show available system generations
[group('darwin')]
generations:
    {{ DARWIN_GENERATIONS }}

# Rollback to previous generation
[group('darwin')]
rollback:
    {{ DARWIN_ROLLBACK }}

# Update flake inputs
[group('workflow')]
update:
    nix flake update

# Update a specific input (e.g., just update-input nixpkgs)
[group('workflow')]
update-input INPUT:
    nix flake update {{ INPUT }}

# Show flake info
[group('workflow')]
info:
    nix flake show

# Show flake metadata
[group('workflow')]
metadata:
    nix flake metadata

# Enter development shell
[group('workflow')]
dev:
    nix develop

# List objects in the configured Cloudflare R2 bucket
[group('r2')]
r2-list PREFIX="":
    #!/usr/bin/env bash
    set -euo pipefail
    R2_PREFIX="{{ PREFIX }}" sops exec-env secrets/cloudflare.yaml bash <<'SCRIPT'
    set -euo pipefail
    prefix="${R2_PREFIX:-}"
    endpoint="$(printenv 'cloudflare-endpoint')"
    bucket="$(printenv 'cloudflare-bucket-name')"
    export AWS_ACCESS_KEY_ID="$(printenv 'cloudflare-access-key-id')"
    export AWS_SECRET_ACCESS_KEY="$(printenv 'cloudflare-secret-access-key')"
    export AWS_DEFAULT_REGION=auto

    args=(
      --endpoint-url "$endpoint"
      s3api list-objects-v2
      --bucket "$bucket"
      --no-cli-pager
      --output json
    )
    if [[ -n "$prefix" ]]; then
      args+=(--prefix "$prefix")
    fi
    if ! command -v jq >/dev/null 2>&1; then
      echo "ERROR: jq is required to format object sizes. Install it with: brew install jq" >&2
      exit 1
    fi
    aws "${args[@]}" | jq -r '
      ["Key", "Size (MB)", "Last Modified"],
      (.Contents[]? | [.Key, ((.Size / 1000000) * 100 | round / 100), .LastModified])
      | @tsv
    ' | column -t -s $'\t'
    SCRIPT

# Backup the sops age key to 1Password as a document
[group('secrets')]
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
[group('secrets')]
edit-secrets FILE="secrets/default.yaml":
    #!/usr/bin/env bash
    set -euo pipefail
    if [ ! -f "{{ FILE }}" ]; then
        echo "File not found: {{ FILE }}"
        exit 1
    fi
    nix shell nixpkgs#sops nixpkgs#age -c sops "{{ FILE }}"

# Generate an age key for sops-nix (idempotent — skips if key exists)
[group('secrets')]
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
[group('darwin')]
clean:
    {{ CLEAN_30D }}

# Clean up all old generations and optimize the Nix store
# (nh path and fallback both collect everything old, then optimize once)
[group('darwin')]
clean-full:
    {{ CLEAN_ALL }}

# Diff current and new configuration
[group('darwin')]
diff:
    #!/usr/bin/env bash
    set -euo pipefail
    nix build .#darwinConfigurations.{{ HOST }}.system --out-link result-diff
    nvd diff /run/current-system result-diff

# Setup work SSH keys and configuration
[group('workflow')]
setup-work-ssh:
    ./scripts/setup-work-ssh.sh

# Check for available updates (pulls if flake.lock changed, notifies via macOS)
[group('workflow')]
check-updates:
    ./scripts/check-for-updates.sh

# Show auto-update service status and trigger manual check
[group('workflow')]
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
