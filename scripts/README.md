# Scripts Directory

This directory contains utility scripts for the Nix configuration.

## Files

- `ai-selector.sh` - Interactive AI assistant picker (`gum`-based); installed to
  `~/.local/bin/ai-selector` (see `modules/home/base.nix`)
- `setup-work-ssh.sh` - Configure separate SSH keys for work repositories
- `setup-yubikey-sudo.sh` - Configure YubiKey for sudo authentication
- `yubikey-sudo-shim.sh` - Notify when sudo auth is required (used by `just switch`; only installed when the laptop lid is closed)
- `check-for-updates.sh` - Check `flake.lock` for upstream changes and notify (`just check-updates`)
- `check-npm-cache.sh` - Report stale npm metadata that breaks `npm install
  <pkg>@latest` and `pi update --extensions` (`just npm-cache-check`)
- `check-kanban-protocol-sync.sh` - Fail if the board protocol quoted in
  `docs/kanban.md` drifts from the plugin's `PROTOCOL_TEMPLATE` (pre-commit hook)
- `README.md` - This file

## AI Assistant Selector

`ai-selector.sh` lets you pick a coding assistant from a menu (Claude Code,
OpenCode, Gemini CLI, GitHub Copilot) using `gum`. It is installed at
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
