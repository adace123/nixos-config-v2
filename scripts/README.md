# Scripts Directory

This directory contains utility scripts for the Nix configuration.

## Files

- `ai-selector.sh` - Interactive AI assistant picker (`gum`-based); installed to
  `~/.local/bin/ai-selector` (see `modules/home/base.nix`)
- `setup-work-ssh.sh` - Configure separate SSH keys for work repositories
- `setup-asix-ethernet.sh` - Install the ASIX AX88179 USB→Ethernet driver
  (`just setup-asix-ethernet`); Homebrew's cask is disabled upstream
- `setup-yubikey-sudo.sh` - Configure YubiKey for sudo authentication
- `yubikey-sudo-shim.sh` - Notify when sudo auth is required (used by `just switch`; only installed when the laptop lid is closed)
- `check-for-updates.sh` - Check `flake.lock` for upstream changes and notify (`just check-updates`)
- `check-npm-cache.sh` - Report stale npm metadata that breaks `npm install
  <pkg>@latest` and `pi update --extensions` (`just npm-cache-check`)
- `check-nix-caches-sync.sh` - Fail if `flake.nix`'s literal `nixConfig` drifts
  from `nix-caches.nix`, the source of truth (pre-commit hook and CI)
- `dathomir-convert.sh` - Convert the `dathomir` OCI instance from its Oracle
  platform image (Ubuntu) to NixOS in place, then activate the flake config
  (`just dathomir-convert`)
- `README.md` - This file

## AI Assistant Selector

`ai-selector.sh` lets you pick a coding assistant from a menu (Claude Code,
Gemini CLI, GitHub Copilot) using `gum`. It is installed at
`~/.local/bin/ai-selector` by `modules/home/base.nix`. Requires `gum` (in
`home.packages`). Run it with:

```bash
ai-selector
```

## Auto-Update Service

The automatic update functionality lives in `modules/darwin/auto-update.nix` as a nix-darwin launchd service, but is **currently disabled** (`services.nix-config-auto-update.enable = false` in `modules/darwin/default.nix`).

For a manual check, run `just check-updates` (which calls `check-for-updates.sh`).

### How It Works (when enabled)

- **Schedule**: Runs daily at 10:00 AM
- **Function**: Checks if `flake.lock` has changes on `origin/main`
- **Notification**: Sends persistent macOS notification when updates are available
- **Action Required**: You manually run `just switch` to apply updates

### Checking Service Status

```bash
just auto-update-status
```

### Manual Trigger

```bash
launchctl start nix-config-auto-update
```

### View Logs

```bash
tail -f /tmp/nix-darwin-update.log
```

### Features

- Only notifies on `flake.lock` changes (dependency updates)
- Waits for network availability
- Persistent notifications (stay until clicked)
- Click notification to open Terminal
- No automatic rebuild (avoids sudo/Touch ID issues)

## npm Cache Check

`check-npm-cache.sh` reports the one npm cache state that silently breaks tag
resolution (`npm install <pkg>@latest`, `pi update --extensions`):

```bash
just npm-cache-check          # or ./scripts/check-npm-cache.sh [npm-cache-dir]
```

**Why it breaks.** npm caches a package's compressed ("corgi") and
full-metadata packuments under the *same* cache key, as two cacache index
records distinguished only by `vary: accept`. `prefer-offline=true` becomes HTTP
cache mode `force-cache`, which serves both without revalidation, so the full
record can lag behind the compressed one. Tag resolution then reads `latest` from
the fresh compressed record, does not find that version in the stale full
record, and aborts:

```text
npm error notarget No matching version found for <pkg>@<version>
```

`--prefer-online` does **not** help (npm checks `preferOffline` first);
`NPM_CONFIG_PREFER_OFFLINE=false` does, because env config outranks `.npmrc`.

**The check** is offline and mechanical: it flags keys whose newest
full-metadata record is more than `MAX_LAG_SECONDS` (default 3600) older than
their newest compressed record. Exit `1` means the cache can serve a wrong
answer for those packages.

**The fix** is `npm cache verify`: it rebuilds the index keeping the newest
record per key, so the stale variant is dropped and refetched, while the ~800 MB
of cached content stays. (`npm cache clean --force` also works but re-downloads
everything.)

See `docs/ai.md` for how this bit Pi's extension updates.

## dathomir conversion

`dathomir-convert.sh` finishes off provisioning the OCI VPS. OpenTofu creates the
instance from an Oracle **platform image** (an Always Free tenancy cannot import a
custom image — `custom-image-count = 0`), and this script replaces that Ubuntu
install with NixOS:

```bash
just dathomir-convert              # default target: dathomir
just dathomir-convert dathomir-1   # when the tailnet name came back suffixed
```

It is deliberately operator-run rather than cloud-init driven: the instance has
no public IP, so an unattended conversion that fails leaves a box reachable only
through OCI's VNC console. Here a failure leaves Ubuntu up and reachable, and the
script is safe to re-run (an instance that is already NixOS skips straight to
activating the flake config, which is built on the host because this workstation
has no aarch64-linux builder).

Mechanically it: copies the Tailscale auth key from `/var/lib/tailscale/` to
`/etc/nixos/` (survives the pivot, unlike `/var`), adds `var/lib/tailscale` to
`/etc/NIXOS_LUSTRATE` so the node keeps its identity, fetches `nixos-infect` at a
pinned revision and verifies its SHA-256 before copying the verified file to the
host (nothing unverified is piped into a root shell), runs it with
`NIXOS_IMPORT=./dathomir-import.nix` (the module copied in from
`infra/dathomir-infect-import.nix`), reboots into NixOS, then runs
`NHOST=dathomir just nixos-deploy <target>`. See [docs/dathomir.md](../docs/dathomir.md).

## USB Ethernet driver

`setup-asix-ethernet.sh` installs the vendor driver for the ASIX AX88179 USB 3.0
gigabit dongle (USB ID `0b95:1790`):

```bash
just setup-asix-ethernet                          # install
./scripts/setup-asix-ethernet.sh --uninstall      # remove
```

The chip is USB vendor-class (`bDeviceClass 0xFF`), so macOS publishes the USB
interface and then binds nothing to it — no `en*`, nothing in Network settings,
which reads as a dead adapter but is a missing driver. Homebrew's
`asix-ax88179` cask would install the same package, but it is disabled upstream
(`disable! date: "2026-09-01", because: :fails_gatekeeper_check`) and `brew`
refuses disabled casks, so it cannot live in `modules/darwin/homebrew.nix`
without failing adoption. The script vendors the package instead, pinned by
SHA-256 and signature-checked before installing.

Approving the DriverKit extension and rebooting are manual steps. On a
Jamf-managed Mac that approval can be policy-blocked. See
[docs/darwin.md](../docs/darwin.md).

## SSH Configuration

### Work SSH Setup

To use separate SSH keys for work repositories:

```bash
just setup-work-ssh
```

This configures automatic SSH key selection based on repository path.

### YubiKey Sudo Setup

To enable YubiKey for sudo authentication:

```bash
./scripts/setup-yubikey-sudo.sh
```

## Legacy Auto-Update

The previous standalone auto-update scripts have been removed in favor of the nix-darwin managed service. The old implementation included:

- `auto-update.sh` - Complex bash script with backup/rollback
- `auto-update.conf` - Configuration file

These have been replaced with a simpler, more reliable notification-only approach.
